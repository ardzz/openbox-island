"""Google Calendar API accounts: OAuth refresh-token fetch converted to ICS."""

import datetime as dt
import json
import shlex
import urllib.error
import urllib.parse
import urllib.request
import zoneinfo

import icalendar

from . import config, fetch

PREFIX = "google:"
AUTH_URL = "https://accounts.google.com/o/oauth2/auth"
TOKEN_URL = "https://oauth2.googleapis.com/token"
EVENTS_URL = "https://www.googleapis.com/calendar/v3/calendars/{}/events"


def calendar_id(account):
    return account.url.removeprefix(PREFIX) if account.url.startswith(PREFIX) else None


def client_path():
    return config.config_path().parent / "google-client.json"


def tokens_path():
    return config.config_path().parent / "google-tokens.json"


def load_client(path):
    """(client_id, client_secret, token_uri, auth_uri) from the installed-app client file."""
    try:
        text = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        raise fetch.FeedError("google-client.json belum ada") from None
    except (OSError, UnicodeDecodeError):
        raise fetch.FeedError("google-client.json tidak valid") from None
    try:
        installed = json.loads(text)["installed"]
        client_id, client_secret = installed["client_id"], installed["client_secret"]
        if not isinstance(client_id, str) or not isinstance(client_secret, str):
            raise TypeError
        token_uri = installed.get("token_uri", TOKEN_URL)
        auth_uri = installed.get("auth_uri", AUTH_URL)
        if not isinstance(token_uri, str) or not isinstance(auth_uri, str):
            raise TypeError
    except (ValueError, KeyError, TypeError, AttributeError):
        raise fetch.FeedError("google-client.json tidak valid") from None
    return client_id, client_secret, token_uri, auth_uri


def load_tokens(path):
    """{account name: refresh token}; {} when the file is missing or unreadable."""
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    if not isinstance(data, dict):
        return {}
    return {str(name): token for name, token in data.items() if isinstance(token, str)}


def request(url, data=None, headers=None):
    """Parsed JSON from URL; DATA (a dict) is sent form-encoded as POST (timeout 15)."""
    if data is None:
        req = urllib.request.Request(url, headers={"User-Agent": fetch.USER_AGENT, **(headers or {})})
    else:
        body = urllib.parse.urlencode(data).encode()
        req = urllib.request.Request(url, data=body, method="POST",
                                     headers={"User-Agent": fetch.USER_AGENT, **(headers or {})})
    with urllib.request.urlopen(req, timeout=15) as handle:
        return json.loads(handle.read().decode("utf-8"))


def _is_invalid_grant(error):
    try:
        body = error.read()
    except Exception:
        return False
    if isinstance(body, bytes):
        try:
            body = body.decode("utf-8")
        except UnicodeDecodeError:
            return False
    try:
        payload = json.loads(body)
    except (TypeError, ValueError):
        return False
    return isinstance(payload, dict) and payload.get("error") == "invalid_grant"


def access_token(account, client):
    client_id, client_secret, token_uri = client[:3]
    refresh = load_tokens(tokens_path()).get(account.name)
    if not refresh:
        raise fetch.FeedError(f"belum login (agenda login {shlex.quote(account.name)})")
    try:
        payload = request(token_uri, data={"client_id": client_id, "client_secret": client_secret,
                                           "grant_type": "refresh_token", "refresh_token": refresh})
    except urllib.error.HTTPError as error:
        if error.code in (400, 401) and _is_invalid_grant(error):
            error.close()
            raise fetch.FeedError(
                f"login ulang (agenda login {shlex.quote(account.name)})") from None
        raise
    token = payload.get("access_token") if isinstance(payload, dict) else None
    if not token:
        raise fetch.FeedError("gagal mengambil")
    return token


def list_events(token, cal_id, start, end):
    items, page_token = [], None
    for _ in range(10):
        params = [("timeMin", start.isoformat()), ("timeMax", end.isoformat()),
                  ("singleEvents", "true"), ("orderBy", "startTime"), ("maxResults", "2500")]
        params += [("eventTypes", kind)
                   for kind in ("default", "focusTime", "outOfOffice", "fromGmail")]
        if page_token:
            params.append(("pageToken", page_token))
        url = EVENTS_URL.format(urllib.parse.quote(cal_id, safe="")) + "?" + urllib.parse.urlencode(params)
        payload = request(url, headers={"Authorization": f"Bearer {token}"})
        items.extend(payload.get("items") or [])
        page_token = payload.get("nextPageToken")
        if not page_token:
            break
    return items


def _moment(value):
    """Aware datetime/date from a Google timestamp dict; absent parts give None.

    A present but malformed timestamp (wrong type, unparsable, unknown
    timeZone, offset-less dateTime without timeZone) raises.
    """
    if value is None:
        return None
    if not isinstance(value, dict):
        raise TypeError("timestamp bukan objek")
    if value.get("dateTime") is not None:
        moment = dt.datetime.fromisoformat(value["dateTime"])
        if moment.tzinfo is None:
            moment = moment.replace(tzinfo=zoneinfo.ZoneInfo(value["timeZone"]))
        return moment
    if value.get("date") is not None:
        return dt.date.fromisoformat(value["date"])
    raise ValueError("timestamp tanpa dateTime/date")


def _join_value(item):
    if item.get("hangoutLink"):
        return item["hangoutLink"]
    data = item.get("conferenceData") or {}
    for entry in data.get("entryPoints") or []:
        if isinstance(entry, dict) and entry.get("entryPointType") == "video" and entry.get("uri"):
            return entry["uri"]
    return ""


def to_ics(items):
    calendar = icalendar.Calendar()
    calendar.add("prodid", "-//openbox-island//agenda//EN")
    calendar.add("version", "2.0")
    for item in items:
        if not isinstance(item, dict) or item.get("status") == "cancelled":
            continue
        if any(isinstance(a, dict) and a.get("self") and a.get("responseStatus") == "declined"
               for a in item.get("attendees") or []):
            continue
        if item.get("start") is None:
            continue
        begin = _moment(item.get("start"))
        if begin is None:
            continue
        event = icalendar.Event()
        uid = item.get("iCalUID") or item.get("id")
        if uid:
            event.add("uid", uid)
        if item.get("summary"):
            event.add("summary", item["summary"])
        if item.get("location"):
            event.add("location", item["location"])
        if item.get("description"):
            event.add("description", item["description"])
        event.add("dtstart", begin)
        finish = _moment(item.get("end"))
        if finish is None:
            finish = begin + dt.timedelta(days=1) if type(begin) is dt.date else begin
        event.add("dtend", finish)
        if item.get("recurringEventId"):
            original = _moment(item.get("originalStartTime")) or begin
            event.add("recurrence-id", original)
        join = _join_value(item)
        if join:
            event.add("x-google-conference", join)
        calendar.add_component(event)
    return calendar.to_ical()


def download(account, start, end):
    cal_id = calendar_id(account)
    token = access_token(account, load_client(client_path()))
    try:
        return to_ics(list_events(token, cal_id, start, end))
    except (urllib.error.HTTPError, fetch.FeedError):
        raise
    except (TypeError, AttributeError, KeyError, ValueError):
        raise fetch.FeedError("respons Google tidak valid") from None

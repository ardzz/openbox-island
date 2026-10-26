# Fitur

Perilaku island: pill ringkas dan kartu, musik YouTube Music (mode Player, Lirik, dan Output), lirik, visualizer, alert, notifikasi, indikator, serta tab Kalender, Cuaca, Tugas, dan Pintasan.

[README](../README.md) · [Fitur](fitur.md) · [Konfigurasi](konfigurasi.md) · [Debug dan tes](debug.md) · [Arsitektur](architecture.md)

## Pill dan kartu

Island menempel di tepi atas layar seperti notch: sisi atasnya rata dengan tepi layar, sudut bawahnya membulat (16 px; kartu yang membesar 22 px), dan dua "telinga" cekung 14 px di kiri dan kanan atas melengkungkan notch ke tepi layar. Tampilan ringkas berukuran 508×44 px (badan 480 px ditambah dua telinga) dengan tinggi yang sama untuk semua halaman: isi idle, media, dan alert ada di baris 36 px di bawah strip 8 px di tepi layar, sedangkan notifikasi dua baris memakai seluruh tinggi 44 px. Telinga selalu menempel di samping pill yang tampil, termasuk pill idle yang sempit. Kartu yang membesar berukuran 508×218 px dan menempel di tepi atas dengan cara yang sama.

Window island bersifat override-redirect (`:wm-ignore true`), jadi Openbox tidak mengelolanya dan klik pada bar tidak bisa menaikkan bar menutupi island.

- Idle: island tetap berupa pill kecil dengan cuaca dan indikator aktivitas; jika tidak ada informasi, pill tetap terlihat kosong. Jam ada di bar. Ada musik: cover + satu baris lirik + enam bar spektrum audio nyata serta indikator aktivitas dalam notch 508×44 px. Visualizer diproses sesuai refresh rate monitor island saat ini (mode aktif `xrandr` pada output di titik 0,0 atau primary; dibulatkan, 1–240 fps, 60 fps bila tidak terbaca), dengan 13 tingkat tinggi bar (4–16 px, langkah 1 px); `ISLAND_VIZ_FPS` (bilangan bulat 1–240) menimpanya. Refresh rate dibaca ulang setiap kali capture audio dimulai ulang (ganti player/stream), tanpa polling. Frame yang tidak berubah tidak dikirim ulang. Bar rata setinggi 4 px saat hening, pause, tidak ada stream yang cocok, atau terjadi error; tidak ada animasi pengganti.
- Hover: membesar menjadi 508×218 px setelah pointer diam di atas island selama 0,3 detik (cover, judul, artis, satu baris lirik, progress, lagu berikutnya untuk YouTube Music, ⏮ ⏯ ⏭). Ganti lagu: membesar 4 detik lalu menciut; selama pointer di atas island, ganti lagu tidak menciutkannya.
- Hover dibaca dari posisi pointer (`xdotool`), bukan dari urutan event enter/leave eww: event itu juga muncul saat aplikasi lain meng-grab pointer dan bisa diproses tidak berurutan.

Scroll ke atas/bawah di atas island ringkas mengubah volume keluaran default sebesar ±5%. Perubahan ini sekaligus membuka bisu (unmute), dengan batas 0–100%.

### Layar penuh

- Layar penuh: selama window aktif dalam mode layar penuh (`_NET_WM_STATE_FULLSCREEN`) menutupi monitor island (monitor 0), ketiga window island ditutup (pill ringkas, kartu, dan [pill kiri](#pill-kiri)); hover, ganti lagu, alert, dan notifikasi tidak membukanya. Notifikasi tetap masuk riwayat dunst (tab Notifikasi). Keluar dari layar penuh atau pindah ke window lain mengembalikan pill ringkas. Dipantau oleh `scripts/fullscreen` lewat event `xprop -spy` (`_NET_ACTIVE_WINDOW` dan `_NET_WM_STATE` window aktif), tanpa polling; dijalankan `island.sh` di samping daemon (bukan `deflisten`, karena eww menghentikan listener saat window-nya ditutup) dan berhenti bersama daemon. `ISLAND_FULLSCREEN_HIDE=0` saat menjalankan `island.sh` mematikannya.

## Tab

- Tab: kartu yang membesar punya tab **Musik** (kartu media), **Kalender** (agenda hari ini sampai 30 hari ke depan), **Cuaca** (kartu cuaca), **Notifikasi** (pusat notifikasi, lihat di bawah), **Tugas** (daftar tugas, lihat di bawah), dan **Pintasan** (tombol pintasan, lihat di bawah). Tab hanya tersedia selama ada isinya: Musik selama YouTube Music memutar atau dijeda (lihat [Musik](#musik)), Kalender selama data kalender tersedia, Cuaca selama cuaca tersedia, Notifikasi selama riwayat dunst berisi notifikasi, Pintasan selama `eww/shortcuts` berisi minimal satu pintasan; Tugas selalu tersedia. Jika lebih dari satu tab tersedia, baris tab kecil tampil di atas kartu: tiap tab berupa ikon redup, dan tab aktif melebar di atas chip abu gelap menjadi ikon, nama, dan badge jumlah beraksen (acara hari ini yang belum berakhir di Kalender, notifikasi di riwayat di Notifikasi, tugas terbuka di Tugas). Nama tab dan jumlahnya juga ada di tooltip ikon. Klik tab untuk memilihnya; scroll ke atas/bawah di atas baris tab berpindah ke tab sebelumnya/berikutnya (memutar, satu perpindahan per 0,5 detik agar satu gerakan touchpad tidak melompati beberapa tab). Hover membuka tab yang terakhir dipilih, atau tab pertama yang tersedia bila tab itu kosong. Ganti lagu selalu membuka tab Musik tanpa mengubah pilihan tersimpan; saat musik berhenti, kartu yang tetap terbuka pindah ke Cuaca.

## Musik

Island hanya menampilkan YouTube Music. Prioritas player diatur di `eww/players` (default `ytm_player,ytermusic,edge`), lihat [Konfigurasi → Player](konfigurasi.md#player).

- `ytm_player` ([ytm-player](https://ytm-player.com)) dan `ytermusic` selalu dianggap YouTube Music.
- Edge hanya tampil bila [bridge YouTube Music](konfigurasi.md#bridge-youtube-music-untuk-edge) membuktikan bahwa lagunya berasal dari tab `music.youtube.com`: status bridge `ytm-browser.json` berumur paling lama 15 detik (`ISLAND_BRIDGE_MAX_AGE_MS`) dan judulnya sama dengan judul MPRIS Edge setelah normalisasi (huruf kecil, hanya huruf dan angka, spasi dirapatkan). Saat ganti lagu, judul MPRIS dan judul bridge boleh berbeda paling lama 5 detik sejak kecocokan terakhir (`ISLAND_BRIDGE_SKEW_MS`).
- YouTube biasa dan media web lain di Edge diabaikan karena judulnya tidak cocok dengan bridge; demikian juga Edge tanpa bridge, bridge yang kedaluwarsa, dan player lain di luar tiga nama tersebut. Dalam keadaan ini island berperilaku seperti tidak ada musik.
- Ekstensi mengirim ulang metadata yang sama setiap 5 detik, jadi tab YouTube Music yang terbuka menjaga status bridge tetap baru. Bila tab ditutup atau ekstensi berhenti, listener `scripts/media` bangun sendiri saat status kedaluwarsa, tanpa menunggu event metadata baru, lalu menyembunyikan musik Edge.

- Ganti lagu: player sempat tidak melaporkan lagu sesaat. Selama itu pill tetap dalam mode musik dan kartu tetap di tab Musik, dengan kerangka abu-abu (cover, judul, artis, lirik, progress) tanpa teks sampai metadata lagu baru tiba. Musik baru dianggap berhenti (island menciut, tab beralih ke Cuaca) bila tidak ada lagu selama 1,5 detik (`ISLAND_MEDIA_GRACE`, detik; `0` = langsung).
- Saat membesar, judul lebih dari 30 karakter dan artis lebih dari 36 karakter bergulir sekitar 5 karakter/detik, dengan jeda 1,2 detik di awal tiap putaran dan pemisah `   ·   `. Teks pendek tetap diam; guliran dimulai ulang saat window dibuka atau lagu berganti, tanpa polling saat menciut.
- YouTube Music: selama player yang tampil adalah `ytm_player`, kontrol diapit tombol tidak suka (kiri) dan suka (kanan). Status suka lagu dibaca sekali per lagu di latar belakang lewat ytmusicapi (`get_watch_playlist`, sekitar 1,5 detik) dan disimpan selama listener berjalan; jawaban lambat untuk lagu sebelumnya diabaikan. Tombol yang aktif terisi dan berwarna aksen. Klik menjalankan `ytm like`/`ytm dislike`, atau `ytm unlike` bila status itu sudah aktif, lalu tampilan langsung berubah. Listener mengikuti state `scripts/media` lewat `inotifywait`, tanpa polling; `ytm status` dipanggil sekali saat lagu berganti untuk mengambil video ID.
- Lagu berikutnya: selama tombol suka tampil, di bawah progress ada satu baris redup berisi ikon antrean lalu `judul — artis` (teks `Berikutnya:` ada di tooltip), dipotong dengan elipsis bila melebihi lebar kartu. Antrean dibaca sekali per lagu dengan `ytm queue` (hanya baca) di latar belakang setelah video ID didapat; jawaban untuk lagu sebelumnya diabaikan dan baris lama langsung hilang saat lagu berganti. Lagu berikutnya dipilih seperti ytm-player sendiri: entri sesudah `current_index`, lagu yang sama saat repeat one, entri pertama saat repeat all tanpa shuffle di akhir antrean. Baris tidak tampil bila lagu yang diputar adalah entri terakhir (termasuk akhir antrean shuffle, karena urutan diacak ulang), tidak berada di posisi `current_index`, atau antrean gagal dibaca. Perubahan antrean tanpa ganti lagu baru terlihat pada lagu berikutnya.
- Headphone: selama output default adalah headset Bluetooth (sink `bluez_*`) atau port headphone/headset kabel, ikon headphone tampil di samping visualizer pada pill musik (ikon Bluetooth atau kabel; merah bila baterai ≤ 20%). Di tab Musik, baris di atas kontrol menampilkan nama perangkat lalu ikon level baterai dan persentasenya (`ULT WEAR`, ikon, `90%`; hanya nama bila baterai tidak terbaca) rata kanan, berbagi baris dengan lagu berikutnya. Speaker dan HDMI tidak menampilkan apa pun. Listener `status` membaca ulang saat event sink/server `pactl subscribe` dan sinyal BlueZ `Connected`/`Battery1.Percentage` (`gdbus monitor`), tanpa polling; nama dan baterai dari `bluetoothctl info`.
- Warna cover: latar halaman tab Musik diwarnai dengan warna dominan cover (`media.color`). Warna diambil dari histogram cover yang diperkecil ke 12×12 piksel dengan ImageMagick dan disimpan di `${XDG_CACHE_HOME:-$HOME/.cache}/eww-island/art-color/` menurut SHA-1 isi berkas cover. Cover yang didominasi abu-abu, cover yang tidak tersedia, dan kerangka saat ganti lagu tidak memberi warna; latar tetap default. Pill ringkas tidak diwarnai.

Tombol suka/tidak suka dan lagu berikutnya memerlukan ytm-player yang sudah login, lihat [Konfigurasi → Tombol suka YouTube Music](konfigurasi.md#tombol-suka-youtube-music).

### Mode tab Musik

Baris atas tab Musik berisi tiga mode: **Player**, **Lirik**, dan **Output**. Mode aktif berwarna aksen. Mode yang dipilih tetap dipakai sampai diganti atau daemon island dijalankan ulang.

- **Player**: tampilan kartu media di atas (cover, judul, artis, satu baris lirik, progress, lagu berikutnya/headphone, kontrol).
- **Lirik**: judul lagu dan tombol kembali ke Player, lalu daftar baris lirik, lihat [Lirik penuh](#lirik-penuh).
- **Output**: daftar output audio, lihat [Output audio](#output-audio).

### Lirik penuh

- Mode Lirik menampilkan paling banyak enam baris: dua baris sebelum baris aktif dan tiga sesudahnya. Dekat awal lirik (atau sebelum baris pertama) jendelanya lebih pendek karena baris sebelumnya belum ada. eww tidak dapat menggulir daftar secara otomatis, jadi jendela ini berpindah per baris mengikuti baris aktif, bukan bergulir halus. Baris panjang dipotong dengan elipsis.
- Lirik tersinkron: baris aktif berwarna aksen dan tebal. Klik baris memindahkan posisi putar ke timestamp baris itu (`playerctl position`), hanya bila lirik yang tampil milik lagu dan player yang sedang tampil. Sesaat setelah ganti lagu, sebelum lirik lagu baru siap, baris lirik lama tidak memindahkan posisi lagu baru.
- Lirik biasa tanpa timestamp (lihat [Lirik YouTube Music](#lirik-youtube-music)): posisi jendela adalah **perkiraan** dari posisi putar dibagi durasi lagu, tanpa sorotan baris aktif. Semua baris tampil redup dan tidak dapat diklik.
- Tanpa baris lirik (termasuk saat hanya judul/artis yang tampil di mode Player), mode Lirik menampilkan `Lirik tidak tersedia`.

### Output audio

- Mode Output mendaftar semua sink PipeWire/PulseAudio dari `pactl`, dengan deskripsi sink sebagai label (nama sink bila deskripsi kosong). Output default berada di urutan pertama dengan tanda ✓ dan warna aksen; sisanya urut menurut label. Tooltip menampilkan label lengkap.
- Paling banyak enam baris tampil; sisanya diringkas menjadi `+N lainnya`. Tanpa sink, mode ini menampilkan `Tidak ada output`.
- Klik satu baris menjadikan sink itu output default lalu memindahkan **semua** stream yang sedang diputar (semua sink input, bukan hanya player musik) ke sink tersebut. Klik beruntun diproses satu per satu. Bila sink sudah hilang saat diklik, tidak ada yang diubah. Bila salah satu stream gagal dipindah, stream lain tetap dipindah.
- Daftar diperbarui dari event sink/server `pactl subscribe`, tanpa polling.

### Visualizer

- Visualizer hanya mengambil stream keluaran milik PID player MPRIS aktif atau proses turunannya, bukan mikrofon, monitor audio sistem, atau sumber audio default sebagai fallback. Metadata dan kontrol MPRIS tetap bekerja jika visualizer tidak mendapat audio.
- Audio visualizer hanya lewat memori/FIFO lokal, tidak disimpan atau diunggah. Unduhan cover tetap menggunakan jaringan.

### Lirik

- Lirik tersinkron dari LRCLIB, dengan NetEase Cloud Music sebagai fallback, tampil miring dan rata tengah pada kedua ukuran island. Untuk `ytm_player`, lirik YouTube Music dicoba lebih dulu (lihat [Lirik YouTube Music](#lirik-youtube-music)). Baris panjang dipotong dengan elipsis, tanpa bergulir atau mengecilkan font; tooltip menampilkan teks lengkap. Posisi MPRIS dibaca setiap 250 ms saat player aktif; listener hanya mengirim perubahan teks/status sinkron, bukan frame berulang. Saat belum ada baris lirik, intro, instrumental, hasil tidak tersedia, atau lookup gagal/timeout tanpa cache positif, judul dan artis asli tampil dengan warna redup.
- LRCLIB tidak memerlukan API key. Pencarian mengirim metadata judul, artis, dan durasi, bukan audio. Cache hasil positif berlaku 30 hari; hasil positif kedaluwarsa masih dipakai jika layanan gagal diakses. Cache negatif berlaku 24 jam hanya jika semua sumber yang dicoba memastikan tidak ada lirik tersinkron; cache negatif yang dibuat tanpa YouTube Music tidak berlaku untuk `ytm_player`. Error jaringan/timeout tidak disimpan sebagai hasil negatif.

### Lirik YouTube Music

Saat player aktif adalah `ytm_player`, listener mengambil video id dari `ytm status` (MPRIS ytm-player tidak membawanya), lalu meminta lirik lewat `ytmusicapi` dengan login ytm-player (`${XDG_CONFIG_HOME:-$HOME/.config}/ytm-player/auth.json`). Lookup berjalan di thread terpisah sehingga pembacaan posisi 250 ms tidak tertahan. Jika `ytmusicapi` tidak terpasang atau `auth.json` tidak ada, sumber ini dilewati tanpa pesan dan LRCLIB/NetEase tetap dipakai.

Urutan prioritas: lirik YouTube Music bertimestamp, lalu lirik tersinkron LRCLIB, NetEase, kemudian lirik YouTube Music biasa (tanpa timestamp), dan terakhir judul/artis. Permintaan bertimestamp yang gagal (misalnya HTTP 400) diulang tanpa timestamp; pada akun yang diuji, YouTube Music hanya memberi lirik biasa.

Lirik biasa tidak tersinkron: baris yang tampil hanya **perkiraan**, yaitu baris lirik dibagi rata sepanjang durasi lagu menurut posisi putar, sehingga bisa mendahului atau tertinggal dari lagu. Baris perkiraan ini tampil dengan warna redup seperti fallback, bukan gaya lirik tersinkron. Lirik biasa disimpan bersama cache negatif selama 24 jam agar sumber tersinkron dicek ulang setelahnya. Kegagalan `ytm status` atau request YouTube Music dianggap gangguan sementara dan mengikuti jadwal retry yang sama.

### Fallback lirik NetEase

Listener mencoba NetEase Cloud Music jika LRCLIB tidak menghasilkan lirik tersinkron yang cocok, termasuk saat LRCLIB gagal sementara. Endpoint NetEase ini tidak resmi dan dapat berubah atau berhenti tersedia. Listener mengirim judul dan artis ke server NetEase untuk pencarian, lalu membandingkan durasi dari hasilnya dengan durasi lagu aktif secara lokal. Audio tidak dikirim; akses tidak memakai login atau cookie.

Judul harus sama setelah normalisasi, termasuk penghapusan akhiran promosi. Jika salah satu nama artis atau alias cocok setelah normalisasi, toleransi durasinya ±2 detik. Jika artis tidak cocok, misalnya karena perbedaan aksara, hasil hanya diterima bila tepat satu kandidat memiliki judul sama dan durasi dalam ±1 detik. Listener membuang baris kredit di awal isi baris, tetapi mempertahankan timestamp lirik. Hasil instrumental, tanpa lirik, atau hanya kredit tidak ditampilkan sebagai lirik.

Lookup menunggu metadata stabil selama 1 detik; fallback judul/artis tetap berubah segera. Request kedua layanan berjarak minimal 200 ms dan memakai cooldown terpisah per host agar gangguan LRCLIB tidak menghalangi NetEase. Jika keduanya belum memberi hasil dan salah satunya gagal sementara, listener menjadwalkan maksimal tiga retry dengan jeda minimum 15, 30, lalu 60 detik, mengikuti `Retry-After` bila lebih lama.

## Aktivitas

Alert menggantikan isi pill sementara, hanya pada tampilan ringkas; tampilan yang sedang membesar tidak berubah. Alert volume, mikrofon, kecerahan, dan Caps Lock bertahan 1,5 detik; alert lain bertahan 3 detik.

| Jenis | Teks |
| --- | --- |
| `volume` | `Volume` atau `Bisu`, dengan persentase volume |
| `mic` | `Mikrofon nyala` atau `Mikrofon mati` |
| `output` | `Output audio` saat sink default atau port aktifnya berganti, dengan nama port aktif (jika sink punya lebih dari satu port) atau nama sink; ikon headphone Bluetooth, headphone, monitor (HDMI/DisplayPort), atau speaker |
| `brightness` | `Kecerahan`, dengan persentase |
| `charging` | `Mengisi daya` saat charger dipasang, dengan persentase (ditambah `· batas 80%` selama mode konservasi aktif); ikon berwarna aksen dan berdenyut beberapa kali |
| `battery` | `Charger dicabut` atau `Baterai penuh`, dengan persentase; juga `Batas pengisian aktif` (80%) atau `Pengisian penuh` (100%) saat mode konservasi baterai Lenovo berubah |
| `battery-low` | `Baterai lemah` saat melewati 20% atau `Baterai kritis` saat melewati 10% ketika daya sedang dipakai; ikon dan meter berwarna merah |
| `wifi` | `Wi-Fi tersambung` dengan nama koneksi, atau `Wi-Fi terputus` |
| `bluetooth` | `Bluetooth tersambung` atau `Bluetooth terputus`, dengan nama perangkat (alias) serta persentase baterai saat tersambung jika perangkat melaporkannya; ikon mengikuti jenis perangkat (headphone, gamepad, mouse, keyboard, ponsel) |
| `vpn` | `VPN tersambung` atau `VPN terputus` dengan nama interface, satu alert per interface; `Tailscale tersambung` dengan nama host perangkat ini, atau `Tailscale terputus`; `Exit node aktif` dengan nama exit node, atau `Exit node dimatikan` |
| `vpn-error` | `Tailscale perlu login` saat Tailscale meminta login atau persetujuan perangkat; ikon berwarna merah |
| `screenshot` | `Tangkapan layar` dengan nama berkas dan thumbnail gambar sebagai pengganti ikon, saat berkas `.png`/`.jpg`/`.jpeg` baru selesai ditulis atau dipindahkan ke folder tangkapan layar |
| `temperature` | `CPU panas` atau `GPU panas` dengan suhunya, sekali saat suhu mencapai batas (CPU 95 °C, GPU 87 °C; ubah dengan `ISLAND_TEMP_CPU`/`ISLAND_TEMP_GPU`); muncul lagi hanya setelah suhu turun di bawah batas − 5 °C. Ikon berwarna merah |
| `capslock` | `Caps Lock nyala` atau `Caps Lock mati` saat status LED Caps Lock keyboard (`/sys/class/leds/*::capslock`, dibaca setiap 0,25 detik) berubah |
| `power` | `Mode daya` dengan nama mode (`Hemat daya`, `Seimbang`, `Performa`, `Daya maksimum`, `Kustom`; nilai lain apa adanya) dan ikon per mode, saat profil daya ACPI (`/sys/firmware/acpi/platform_profile`, misalnya lewat Fn+Q di Lenovo Legion; dibaca setiap 2 detik, ubah dengan `ISLAND_POWER_INTERVAL`) berubah |

Folder tangkapan layar: `ISLAND_SCREENSHOT_DIR` jika diset, selain itu `$(xdg-user-dir PICTURES)/Screenshots`, sama dengan `ob-screenshot`/Satty. Jika folder Gambar XDG belum diatur, `xdg-user-dir` menjawab `$HOME`, sehingga folder yang dipantau adalah `~/Screenshots`. Folder dibuat jika belum ada.

Suhu dibaca langsung dari hwmon (`/sys/class/hwmon`) setiap 5 detik (`ISLAND_TEMP_INTERVAL`), tanpa `sensors` atau `nvidia-smi` agar GPU diskrit tidak terbangun. Sensor CPU berlabel `CPU Temperature`, `Package id 0`, atau `Tctl` (urutan prioritas); sensor GPU berlabel `GPU Temperature`. Tanpa sensor yang cocok, alert suhu tidak aktif. Saat island dimulai dalam kondisi sudah panas, alert baru muncul setelah suhu turun lalu naik lagi.

Mode konservasi baterai Lenovo dibaca dari `ISLAND_CONSERVATION` jika diset, selain itu dari `/sys/bus/platform/devices/VPC2004:*/conservation_mode`, setiap 5 detik (`ISLAND_CONSERVATION_INTERVAL`). Status saat island dimulai tidak memunculkan alert. Tanpa berkas tersebut, alert konservasi tidak aktif dan alert `charging` tidak berubah.

VPN diperiksa setiap 10 detik (`ISLAND_VPN_INTERVAL`). VPN umum dibaca langsung dari `/sys/class/net`: interface tun (bukan tap, agar interface VM seperti `vnet0` tidak terhitung), WireGuard, atau `ppp*` yang tidak berstatus `down`; `tailscale*` dikecualikan. Tailscale dibaca dengan `tailscale status --json` tanpa root; nama exit node dicari hanya saat exit node berganti. Tanpa `tailscale` atau saat daemon mati, Tailscale dianggap tidak tersambung tanpa pesan error. Kondisi saat island dimulai tidak memunculkan alert.

## Notifikasi

Notifikasi dunst tampil di pill ringkas menggantikan isi idle atau media (musik tetap berjalan): ikon aplikasi (gambar dari path ikon notifikasi, selain itu ikon lonceng), ringkasan tebal, dan satu baris isi yang dipotong dengan elipsis. Markup dibuang dan entitas HTML diubah menjadi teks biasa. Tiap notifikasi bertahan 4 detik (`ISLAND_NOTIFY_SECONDS`), lalu tampilan sebelumnya kembali. Notifikasi berikutnya antre dan tampil bergantian; jika lebih dari tiga menunggu, sisanya digabung menjadi satu entri `+N notifikasi` di akhir antrean. Pembaruan dengan ID yang sama, atau notifikasi dari aplikasi dengan stack tag yang sama, menggantikan entri lama di tempatnya. Alert selalu didahulukan: notifikasi yang sedang tampil berhenti menghitung selama alert tampil lalu melanjutkan sisa waktunya, dan notifikasi baru menunggu sampai alert hilang. Selama island membesar, notifikasi ditunda dengan cara yang sama sampai island menciut; hover di atas notifikasi tidak membesarkan island. Saat Jangan Ganggu dunst aktif, notifikasi tidak tampil di island.

Semua notifikasi, termasuk yang kritis, hanya tampil di island (tanpa popup dunst); notifikasi kritis diberi aksen merah. Klik pada notifikasi menutupnya dari island dan membuka aplikasinya: window aplikasi yang terlihat diaktifkan dengan `xdotool`, dicari lewat `StartupWMClass` desktop entry, ID desktop entry, lalu nama aplikasi; jika tidak ada window dan notifikasi membawa desktop entry, aplikasi dijalankan dengan `gtk-launch`. Klik pada `+N notifikasi` hanya menutupnya.

Cara launcher menyembunyikan popup dunst dijelaskan di [Konfigurasi → Integrasi dunst](konfigurasi.md#integrasi-dunst).

### Tab Notifikasi

Tab **Notifikasi** di kartu yang membesar adalah pusat notifikasi ala NotchNook. Isinya riwayat dunst (`dunstctl history`): karena popup disembunyikan, dunst menyimpan setiap notifikasi di sana beserta ID-nya, riwayat itu tetap ada saat island dijalankan ulang, dan `history-rm`/`history-clear` langsung bekerja padanya. Kegagalan launcher (`eww-island`) dan OSD volume/kecerahan tidak ikut; salinan lama dengan ID yang sama atau aplikasi dan stack tag yang sama (misalnya progres unduhan) diwakili salinan terbaru. Maksimal 4 baris tampil, terbaru di atas: ikon (gambar dari path ikon, selain itu lonceng), ringkasan tebal dan waktu relatif (`baru saja`, `5 mnt`, `2 jam`, `3 hari`), lalu satu baris isi redup dan nama aplikasi di kanan. Scroll di atas daftar menggeser ke notifikasi yang lebih lama; `+N lainnya` menghitung sisanya. Klik baris membuka aplikasinya seperti klik pada pill (desktop entry diingat dari `notify-hook`, karena riwayat dunst tidak menyimpannya) lalu menghapusnya dari riwayat; **Hapus semua** mengosongkan riwayat. Badge tab aktif menghitung notifikasi di riwayat. Selama tab lain yang tampil, titik aksen pada ikon lonceng menandai notifikasi yang belum dibaca, yaitu yang datang setelah tab terakhir dilihat. Listener `scripts/notif` membaca riwayat hanya saat ada notifikasi baru, klik, hapus, atau island dibuka; selama kartu terbuka waktu relatif diperbarui tiap menit.

## Indikator

Indikator tampil pada pill idle dan media: titik merah dengan durasi berarti layar sedang direkam, titik kuning berarti mikrofon dipakai, titik hijau berarti kamera dipakai, dan ikon lonceng dicoret berarti Jangan Ganggu dunst aktif. Tooltip mikrofon dan kamera mencantumkan aplikasi yang memakainya. Deteksi kamera hanya melihat proses milik pengguna yang sama.

Perekaman layar terdeteksi dari proses milik pengguna yang sama: `ffmpeg` dengan format input `-f x11grab` atau `-f kmsgrab`, atau OBS (`obs` maupun helper `obs-ffmpeg-mux`) yang sedang menulis berkas `.mkv`/`.mp4`/`.mov`/`.flv`/`.ts`/`.webm`. Saat tidak merekam, `/proc` diperiksa setiap 2 detik (`ISLAND_REC_INTERVAL`); selama merekam, durasi sejak rekaman pertama terdeteksi diperbarui setiap detik dan tooltip menyebut aplikasinya.

## Cuaca

Cuaca berasal dari wttr.in. Pill idle menampilkan ikon, suhu, dan kota, rata tengah. Hover di atas island idle selama 0,3 detik membuka kartu detail 508×218 px: kondisi cuaca, suhu, kota dan wilayah, waktu matahari terbit/terbenam, suhu terasa, kelembapan, angin, dan indeks UV sebagai chip ikon dan nilai (nama tiap chip ada di tooltip), serta prakiraan 3 hari dalam tile dengan suhu maksimum/minimum dan peluang hujan. Jika cuaca tidak tersedia, hover idle membuka tab lain (paling tidak Tugas). Cuaca diperbarui setiap 30 menit, dicoba ulang setelah 5 menit jika gagal, dan cache dapat dipakai selama 3 jam. Listener yang dimulai ulang (misalnya island kembali setelah layar penuh) memakai cache yang berumur kurang dari 30 menit tanpa mengambil ulang.

Warna ikon cuaca (pill, kartu, dan prakiraan) mengikuti kondisi lalu suhu: hujan biru, badai magenta, salju putih, kabut dan berawan abu; selain itu ≥33° merah (panas), ≤15° cyan (dingin), cerah malam biru pucat, ≥28° jingga (hangat), cerah kuning. Prakiraan memakai suhu maksimum dan selalu dianggap siang. Warna berasal dari palet tema bar.

Urutan lokasi, GeoClue, dan privasi: [Konfigurasi → Lokasi cuaca](konfigurasi.md#lokasi-cuaca).

## Tugas

Tab **Tugas** adalah daftar tugas singkat yang selalu tersedia (agar tugas pertama bisa ditambahkan), sehingga hover selalu membuka kartu; badge tab memuat jumlah tugas yang belum selesai. Daftar disimpan di `${XDG_DATA_HOME:-$HOME/.local/share}/eww-island/todo.json` sehingga tetap ada setelah reboot; perubahan ditulis atomik di bawah `flock`, dan file rusak dibaca sebagai daftar kosong lalu disisihkan sebagai `todo.json.corrupt` saat perubahan berikutnya. Urutan: tugas terbuka terbaru di atas, lalu tugas selesai (dicoret dan redup) yang terakhir diselesaikan di atas. Maksimal 4 baris tampil; scroll di atas daftar menggeser baris, `+N lainnya` menghitung sisanya. Kotak centang menandai selesai/belum, `×` menghapus, **Bersihkan selesai** menghapus semua tugas selesai. Kartu island tidak bisa menerima fokus keyboard di Openbox (window override-redirect), jadi **+ Tambah** menutup kartu lalu meminta teks lewat `rofi -dmenu -p Tugas`; teks dirapikan menjadi satu baris (maksimal 200 karakter) dan teks kosong diabaikan. Dari terminal: `scripts/todo add TEKS | toggle ID | remove ID | clear-done`.

Semua form rofi island (teks Tugas dan item prep) memakai tema `eww/rofi/island.rasi`: panel hitam selebar kartu yang turun dari notch, dengan chip prompt aksen dan placeholder petunjuk. Warna teks dan font mengikuti palet bar (`eww/_colors.scss`) bila ada. Tema rofi global (`~/.config/rofi`) tidak diubah.

### Deadline

Deadline bersifat opsional dan diatur dengan penanggal di dalam kartu, tanpa rofi. Setelah **+ Tambah** meminta teks lewat rofi, tugas langsung ditambahkan tanpa deadline dan kartu membuka tab Tugas dengan penanggal terbuka untuk tugas baru itu; menutup penanggal dengan cara apa pun membiarkan tugas tanpa deadline. Tombol **󰃰** di setiap baris (atau `scripts/todo due ID` dari terminal) membuka penanggal yang sama untuk tugas itu di dalam kartu; bila kartu belum terbuka, kartu dibuka pada tab Tugas.

Selama penanggal terbuka, ia menggantikan daftar Tugas (ukuran kartu tetap 508×218). Di kiri ada kalender satu bulan: header `Bulan Tahun` di antara panah kiri dan kanan, baris hari `Sn Sl Rb Km Jm Sb Mg` (Senin pertama), dan selalu 6 baris minggu berisi 7 hari. Hari ini berbingkai aksen, hari terpilih terisi aksen, hari dari bulan lain redup, dan hari sebelum hari ini redup serta tidak bisa dipilih. Panah kiri/kanan hanya menggeser bulan yang tampil; memilih hari hanya mengubah tanggal. Di kanan tampil teks tugas (terpotong), ringkasan terpilih seperti `Jum 30 Okt · 17:00`, dan baris waktu `Jam HH : MM`: scroll atau tombol panah atas/bawah pada jam menggeser ±1 (membungkus 0–23) dan pada menit ±5 (membungkus 0–55). Chip `09:00`, `12:00`, `15:00`, dan `17:00` menetapkan jam sekaligus.

Saat penanggal dibuka, tanggal dan waktu awal adalah deadline tugas yang sudah ada bila ada (menit dipertahankan apa adanya, termasuk yang bukan kelipatan 5); selain itu tanggalnya hari ini bila waktu sekarang masih sebelum hari ini pukul `ISLAND_DEADLINE_TIME` (bawaan 17:00) dan besok bila sudah lewat, dengan waktu `ISLAND_DEADLINE_TIME`. Bulan yang tampil adalah bulan tanggal terpilih. **Simpan** menyimpan deadline dan menutup penanggal, **Tanpa deadline** menghapus deadline dan menutup, dan **Batal** menutup tanpa mengubah apa pun. Menciutkan kartu juga menutup penanggal tanpa mengubah deadline.

Chip deadline tampil di samping teks: redup untuk deadline yang masih jauh (misalnya `Jum 17:00`), kuning jika kurang dari 24 jam (misalnya `besok 09:00`), dan merah dengan label `terlambat` jika sudah lewat. Tugas tanpa deadline tidak menampilkan chip. Dari terminal: `scripts/todo add TEKS --due EPOCH`, `scripts/todo set-due ID EPOCH|none`, atau `scripts/todo due ID` untuk membuka penanggal di kartu.

Pengingat H-1 dan hari H dikirim pukul 09:00 secara bawaan sebagai notifikasi aplikasi **Tugas**, dengan judul `Deadline besok · HH:MM` atau `Deadline hari ini · HH:MM`; notifikasinya tetap tersimpan di tab **Notifikasi**. Jika beberapa pengingat terlewat, hanya yang terbaru dikirim. Tugas selesai tidak diingatkan; mengubah deadline mengaktifkan ulang pengingat. Waktu dan interval dapat diatur lewat [variabel lingkungan](konfigurasi.md#variabel-lingkungan).

## Kalender

Tab **Kalender** menampilkan jadwal dari hari ini sampai 30 hari ke depan dari beberapa kalender iCal, dengan titik warna per akun. Baris hari ini tampil `HH:MM–HH:MM`; hari lain diawali harinya (`Besok 09:00–10:00`, `Sen 2 Nov 09:00–10:00`). Empat baris tampil sekaligus; posisi awal dimulai dari acara pertama yang belum berakhir. Scroll ke atas untuk melihat acara sebelumnya atau ke bawah untuk melihat sisanya. Acara yang sudah lewat redup, acara berlangsung disorot, dan waktu acara yang segera dimulai berwarna kuning. Acara seharian diringkas dalam satu baris yang diawali tanda `Seharian`. Badge tab Kalender menghitung acara hari ini yang belum berakhir. Acara yang ditolak disembunyikan jika EMAIL akun diisi. Rentang hari diatur lewat `ISLAND_CAL_DAYS` (lihat [variabel lingkungan](konfigurasi.md#variabel-lingkungan)).

### Menyiapkan kalender

1. Pasang paket Arch: `sudo pacman -S --needed python-icalendar python-recurring-ical-events`.
2. Untuk setiap kalender Google, buka Settings → pilih kalender → Integrate calendar → salin **Secret address in iCal format**.
3. Buat direktori `~/.config/openbox-island`, lalu berkas `~/.config/openbox-island/calendars` dengan satu akun per baris:

   ```text
   # NAME | #RRGGBB | EMAIL | URL
   Kantor | #4f8cff | nama@example.com | https://calendar.google.com/calendar/ical/ALAMAT-RAHASIA/basic.ics
   Pribadi | #34c759 | | https://calendar.google.com/calendar/ical/ALAMAT-RAHASIA-LAIN/basic.ics
   ```

   Ganti URL contoh dengan alamat rahasia kalender masing-masing. EMAIL boleh kosong; baris berawalan `#` adalah komentar.
4. Batasi akses: `chmod 600 ~/.config/openbox-island/calendars`.
5. Jalankan `~/.config/eww-island/scripts/agenda check`. Setiap akun menampilkan `NAME: OK, …` atau error, tanpa mencetak URL. Jalankan ulang island setelah konfigurasi siap.

Tombol **Join** tersedia pada acara yang memiliki tautan rapat dan belum berakhir. Klik menutup kartu lebih dulu, lalu membuka tautan. Data diambil ulang setiap 300 detik; tab membaca data lokal setiap 2 detik. Saat offline, feed cache tetap dipakai dengan catatan `diperbarui HH:MM`.

Pengingat dikirim sebagai notifikasi aplikasi **Kalender** 10 menit sebelum rapat (`Meeting 10 menit lagi · HH:MM`) dan saat mulai (`Meeting dimulai · HH:MM`), lalu kartu membuka tab Kalender selama 10 detik. Atur waktunya lewat [variabel lingkungan](konfigurasi.md#variabel-lingkungan); `ISLAND_MEETING_BEFORE` kosong mematikan pengingat sebelum rapat.

Alamat iCal rahasia adalah kata sandi: siapa pun yang memilikinya dapat membaca kalender. Simpan hanya di berkas konfigurasi di luar repo, jangan masukkan ke commit atau screenshot. Cache kalender tersimpan di `~/.cache/eww-island/calendar`.

### Akun Google Calendar API

Gunakan akun API bila akun tidak bisa memberi alamat iCal rahasia atau hanya membagikan status sibuk/luang (free/busy), misalnya akun kantor dari Google Workspace. Akun seperti ini dibaca lewat Google Calendar API dengan login OAuth baca-saja, bukan alamat iCal.

1. Di [Google Cloud Console](https://console.cloud.google.com/), buat atau pilih project di bawah organisasi kantor, lalu aktifkan **Google Calendar API**.
2. Di layar persetujuan OAuth (OAuth consent screen), pilih **Internal** bila tersedia. Bila harus **External**, terbitkan aplikasinya (*In production*), karena status *Testing* membuat login kedaluwarsa setelah 7 hari. Tambahkan scope `https://www.googleapis.com/auth/calendar.readonly`.
3. Buat kredensial **OAuth client ID** bertipe **Desktop app**, lalu unduh berkas JSON-nya ke `~/.config/openbox-island/google-client.json` dan batasi aksesnya: `chmod 600 ~/.config/openbox-island/google-client.json`.
4. Tulis baris akun dengan `google:<calendarId>` sebagai alamatnya; `primary` adalah kalender utama, id kalender lain juga bisa dipakai:

   ```text
   Kantor | #4f8cff | nama@kantor | google:primary
   ```

5. Login sekali dari terminal, lalu periksa:

   ```bash
   ~/.config/eww-island/scripts/agenda login Kantor
   ~/.config/eww-island/scripts/agenda check
   ```

   Perintah `login` membuka browser untuk persetujuan Google, mencetak tautan yang sama bila browser tidak terbuka, dan menyimpan token di `~/.config/openbox-island/google-tokens.json` (mode 600). Ulangi login untuk setiap akun `google:`.

Berkas `google-tokens.json` memberi akses baca ke kalender seperti kata sandi: simpan hanya di luar repo dan jangan masukkan ke commit atau screenshot. Cabut aksesnya kapan pun di Google Account → Security → third-party access; admin Workspace juga bisa memblokir aplikasi ini.

### Persiapan meeting

Template persiapan meeting disimpan di `${ISLAND_PREP:-${XDG_CONFIG_HOME:-$HOME/.config}/openbox-island/prep}`. Satu baris berisi satu seri meeting: `POLA | SEBELUM | item; item; …`. Baris kosong dan baris berawalan `#` diabaikan. `POLA` dicocokkan tanpa membedakan huruf besar/kecil sebagai bagian dari judul meeting; baris pertama yang cocok dipakai. Contoh:

```text
# POLA | SEBELUM | item; item; …
Weekly Report | 2j | Report progres; Plan minggu depan
Standup | 30m | Baca catatan; Siapkan blocker
Retro | 1h | Kumpulkan catatan sprint
```

`SEBELUM` boleh kosong (bawaan `${ISLAND_PREP_BEFORE:-2j}`), `Nm` untuk N menit sebelum mulai, `Nj` untuk N jam sebelum mulai, dan `Nh` untuk N hari sebelumnya pukul `${ISLAND_DEADLINE_TIME:-17:00}`. Item dipisah `;`, dirapikan, dan dibatasi 20 item per template. Baris tanpa item, dengan `POLA` kosong, atau dengan `SEBELUM` tidak dikenal dilewati dengan pesan `prep: baris N dilewati` di stderr.

Worker alert memeriksa agenda yang masih `ok` dan membuat satu item Tugas untuk setiap item template pada meeting yang mulai dalam `ISLAND_PREP_AHEAD` jam (bawaan 24 jam; isi kosong menonaktifkan) dan belum dicatat di ledger `${XDG_DATA_HOME:-$HOME/.local/share}/eww-island/prep-made`. Item dibuat dengan teks `<judul> · <item>`, deadline pada waktu `SEBELUM` (atau jam mulai meeting bila waktu itu sudah lewat), dan field `prep` berisi ID baris agenda. Ledger berisi baris `ID START`; setelah item dibuat, menghapus item Tugas tidak membuatnya lagi untuk occurrence yang sama. Ledger dibersihkan dari baris yang mulai lebih dari 7 hari lalu pada penulisan berikutnya. Worker berjalan sebagai sumber alert `prep` setiap `ISLAND_PREP_INTERVAL` detik (bawaan 60).

Item juga bisa diatur dari tombol berikon daftar pada baris Kalender (tooltip **Atur prep**): kartu ditutup dulu, lalu rofi bertanya `Item prep untuk <judul>; pisahkan dengan ;` dengan item saat ini sebagai isian awal. Menyimpan jawaban memperbarui baris template pertama yang cocok dengan judul (mempertahankan `POLA` dan `SEBELUM`-nya) atau menambah baris baru dari judul meeting; jawaban kosong menghapus baris itu, membatalkan rofi tidak mengubah apa pun, dan lebih dari 20 item dibuang sisanya. Jalan pintas ini menjalankan sinkronisasi sesudahnya, jadi item untuk meeting yang mulai dalam jendela juga langsung dibuat. Jalankan `scripts/prep sync` di terminal untuk menjalankan satu sinkronisasi dan melihat baris template yang dilewati.

Tab Kalender menampilkan chip `Prep N/M` pada baris yang item prep-nya sudah dibuat: kuning selama belum semua selesai, aksen setelah selesai. Pill kiri menampilkan ` · Prep N/M` setelah waktu meeting dengan warna yang sama. Selama item untuk meeting itu masih ada yang belum selesai, isi pengingat meeting menjadi `<judul> · Prep N/M belum selesai`; setelah semua selesai atau bila tidak ada item prep, isi pengingat tetap judul meeting saja.

## Pill kiri

Pill hitam di pojok kiri atas layar, bergaya sama dengan pill status bar: selalu menampilkan rapat yang perlu diperhatikan dari agenda Kalender dan deadline Tugas terbuka yang paling dekat, masing-masing sebagai segmen tersendiri. Jika keduanya ada, keduanya tampil dipisah garis tipis. Pill ini adalah window `island-upcoming` yang dibuka `island.sh` bersama pill ringkas dan ikut disembunyikan bersamanya saat layar penuh (lihat [Layar penuh](#layar-penuh)), lalu dibuka lagi saat island kembali.

- Rapat diambil dari data agenda yang sama dengan tab Kalender (hanya bila kalender terbaca baik), dari acara yang belum berakhir, dalam urutan jadwal: yang sedang berlangsung tampil `sampai HH:MM` (jam berakhirnya) berwarna aksen; yang mulai dalam 15 menit tampil hitungan mundur `Nm` (menit dibulatkan ke atas) berwarna kuning; keduanya menawarkan tombol **Join** bila acara punya tautan rapat https. Rapat berikutnya hari ini tampil jam mulainya `HH:MM`; bila hari ini sudah habis, rapat berikutnya pada hari lain tampil dengan hari dan jam mulainya (misalnya `Besok 09:00` atau `Sen 26 Okt 09:00`).
- Deadline menampilkan tugas terbuka dengan deadline paling awal, dengan label dan warna yang sama seperti chip pada tab Tugas: merah `terlambat` bila sudah lewat, kuning bila kurang dari 24 jam. Bila ada deadline terbuka lain yang jatuh tempo dalam 24 jam, jumlahnya tampil sebagai `+N` di sebelahnya.
- Rapat dengan item prep menampilkan ` · Prep N/M` setelah waktu rapat (kuning selama belum selesai, aksen setelah selesai). Bila tidak ada rapat maupun deadline, pill menampilkan `Kosong hari ini`; kliknya membuka tab Kalender.
- Klik segmen rapat membuka kartu pada tab Kalender, klik segmen deadline membuka kartu pada tab Tugas; kartu terbuka selama 10 detik lalu mengikuti aturan hover seperti biasa. Bila tab yang dituju sedang tidak tersedia (misalnya Kalender belum dikonfigurasi), klik tidak membuka apa pun, bukan tab lain. Klik **Join** membuka tautan rapat.
- Isi dibaca ulang dari berkas agenda dan daftar Tugas setiap `ISLAND_UPCOMING_TICK` detik (bawaan 5), dan hanya berubah tampilan bila isinya berubah.

## Pintasan

Tab **Pintasan** berisi tombol ikon berlabel, tiga per baris, dibaca dari `eww/shortcuts` (perubahan langsung terbaca lewat `inotifywait`). Satu baris per tombol: `IKON | LABEL | PERINTAH`, opsional `| dnd` agar tombol menyala selama Jangan Ganggu dunst aktif; baris kosong dan baris berawalan `#` diabaikan, baris rusak dilewati dengan peringatan di log. Bawaan: Screenshot (`ob-screenshot --area`), Color picker (`ob-colorpicker`), Kunci layar (`betterlockscreen --lock`), Jangan ganggu (`dunstctl set-paused toggle`), Bluetooth (`rofi-bluetooth`), Daya (`rofi-powermenu`). Klik menutup kartu lebih dulu (agar tidak ikut tertangkap screenshot atau color picker), lalu menjalankan perintah lewat `sh` di sesi sendiri (`setsid`) tanpa output ke eww. Jika programnya tidak ditemukan, muncul notifikasi "Perintah tidak ditemukan". Karena tab ini selalu ada, hover di atas pill idle kini selalu membuka kartu; Musik, Cuaca, dan Notifikasi tetap didahulukan bila belum ada tab tersimpan.

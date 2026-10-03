PHMN - icon aplikasi iOS (kupu-kupu & bilah)

AppIcon.appiconset/
  Siap pakai di Xcode 15 ke atas. Salin folder ini ke dalam Assets.xcassets
  (ganti AppIcon.appiconset yang lama). Isinya:
    AppIcon-Light.png  1024x1024  tampilan default (Any)
    AppIcon-Dark.png   1024x1024  tampilan Dark (iOS 18+)
  Slot Tinted dibiarkan kosong; iOS membuat versi tinted otomatis dari icon default.
  PNG tanpa kanal alpha dan tanpa sudut membulat (iOS yang memotong sudutnya).

png/light, png/dark
  Ukuran lama per perangkat (180, 167, 152, 120, 87, 80, 76, 60, 58, 40, 29, 20 px)
  untuk proyek yang masih memakai daftar ukuran manual.

svg/
  Sumber vektor kedua versi, untuk diedit atau diekspor ulang.

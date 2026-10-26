---
title: nonGitLine
type: proje
tags: [arac, git]
status: planlama
updated: 2026-10-26
---

# nonGitLine

Kaynak koddaki `//!!` ile başlayan kişisel not satırları diskte kalır, commit'e ve GitHub'a girmez.

```
Disk (yerel)                         Commit / GitHub
1  //!! gite pushlanmayacak not      1  code1
2  code1                       →     2  code2
3  code2
```

Satır tamamen çıkarılır; yerine boş satır bırakılmaz.

## Kapsam (v1)

- Sadece **tam satır** notlar: satırın baştaki boşluklardan sonra `//!!` ile başlaması gerekir. `code; //!! not` gibi satır sonu notları silinmez; commit durdurulur.
- Diller: Java (`*.java`) ve C# (`*.cs`).
- Notlar sadece bu reponun `.git/` klasöründe yaşar. Fresh clone'da ya da başka makinede görünmez. Bu tasarım gereği böyle.

## Kullanım

```bash
cd <java-ya-da-csharp-reposu>
"/Users/beraterkul/Documents/Obsidian/Obsidian-Vault/01_Projects/nonGitLine/nongitline" install
```

Sonrasında `git add / commit / push` her zamanki gibi kullanılır. `uninstall` kurulumu geri alır. Kurulum script'in tam yolunu hook'lara ve `.git/config`'e yazar. Script taşınırsa her repoda `install` tekrar çalıştırılmalı.

| Durum | Ne olur |
| --- | --- |
| `//!! not` satırı | Commit'e girmez, diskte kalır |
| `int x = 5; //!! not` | Commit durur. Sadece tam satır notlar desteklenir. |
| `// !! not` | Commit durur, çünkü işaret yanlış yazılmış gibi görünüyor |
| Text block / `@"..."` içinde satır başında `//!!` | Veri sayılır ve silinmez. Commit yine de durur ve sorar; bilerek yazıldıysa `--no-verify` ile geçilir |
| Not bir şekilde commit'e sızdı | `push` reddedilir |
| Not ekledin ya da sildin, `git add` yapmadın | `git status` dosyayı ` M` gösterir ama `git diff` boştur. Git, boyut değişince içeriğe bakmıyor. `git add` yapınca düzelir. Bu sırada git dosyanın üzerine yazmayı da reddeder, yani not güvende kalır. |
| `pull` / `rebase` / `stash` / branch değiştirme / `reset --hard` | Notlar eski komşu satırlarına göre yerine konur |
| Notun üstündeki ve altındaki satır upstream'de silindi | Not **yetim** olur: diske yazılmaz ama saklanır ve uyarı basılır |

### Yetim notlar

```bash
nongitline orphans                 # yetimleri, eski komşu satırlarıyla listeler
nongitline orphans --drop A.java   # o dosyanın yetimlerini unutur
```

Yetim notlar, git o dosyayı her yazdığında tekrar denenir. Eski komşu satır dosyada **tek bir yerde** aynen geçiyorsa not oraya konur. Notu elle yerine yapıştırırsan `--drop` ile listeden silebilirsin.

Testler: `./test.sh`. Testler sistem Python'ı ile (`/usr/bin/python3`, 3.9) çalışır, çünkü Dock'tan açılan IntelliJ de bu Python'ı kullanır.

## Nasıl çalışıyor

- **clean filter:** `git add` sırasında dosyayı notsuz hâle getirir ve index'e bu hâli gider. Diskteki dosyaya dokunulmaz.
- **smudge filter:** git dosyanın üzerine yazdığında (pull, merge, rebase, stash, checkout, reset) notları bağlam satırlarına göre geri yerleştirir. Yerleştiremediği notu silmez; **yetim** olarak `.git/nongitline/` içinde saklar ve uyarı basar.
- **pre-commit:** satır sonuna yazılmış ya da yanlış yazılmış işaretleri yakalar.
- **pre-push:** gönderilecek commit'lerde not kalmışsa push'u reddeder.

Ayarlar yereldir (`.git/config`, `.git/info/attributes`) ve commit'e girmez.

### Neden smudge şart: asıl tehlike `pull`

Clean filter kullanınca git, notlu dosyayı "değişmemiş" sayar, çünkü temiz hâli index'tekiyle aynıdır. Bu yüzden dosyanın üzerine sormadan yazar. `fetch` diske dokunmaz, güvenlidir. Ama upstream'in dokunduğu bir dosyada `pull` (merge ya da rebase), conflict, `stash`/`--autostash`, branch değiştirme ve `reset --hard` notları siler. Smudge bu silinmeyi telafi eder.

### Faz 0 spike sonuçları (git 2.50.1, 2026-10-26)

Test, `sed` ile yazılmış basit bir clean filter ve her çağrıyı log'layan, içeriği değiştirmeden geçiren bir smudge filter ile yapıldı.

| Durum | Sonuç |
| --- | --- |
| Notlu dosya, `add` edilmeden önce | `status` dosyayı ` M` gösteriyor. Git boyut farkını görünce içeriğe bakmıyor. |
| Bu hâldeyken upstream'in değiştirdiği dosyaya `pull` | Reddediliyor ("Please commit your changes or stash them"), not güvende |
| `add` ve commit sonrası | Disk notlu ama `working tree clean`. Git dosyayı temiz sayıyor. |
| `pull` (merge), upstream dosyaya dokunmuş | **Not silindi.** Smudge çağrıldı. |
| `pull` sırasında conflict | Conflict marker'lı dosya smudge'dan geçti. **Not silindi.** |
| `stash` / `stash pop` | Stash'e temizlenmiş içerik girdi. **Not silindi.** İki kez smudge çağrıldı. |
| Branch değiştirme | **Not silindi.** Smudge çağrıldı. |
| `add -p` / `git diff` | Not satırları diff'te hiç görünmüyor |
| `required=true` iken clean çökerse | `git add` exit 128 veriyor, index değişmiyor |

**Sonuç:** notu silen her senaryoda git smudge'ı çağırıyor. Yani notları geri yerleştirmek için tek bir giriş noktası yeterli; plan geçerli.

## Fazlar

- [x] Faz 0: Kurulum ve git davranışlarının doğrulanması (spike)
- [x] Faz 1: Clean, Java/C# lexer'ı, install, pre-commit/pre-push check, yedek
- [x] Faz 2: Smudge, not anchoring, yetim yönetimi
  - Not deposu: `.git/nongitline/notes/<path>.json`. İçinde son görülen temiz içerik, not blokları ve yetimler var. Ayrıca son 20 notlu sürüm `.git/nongitline/backup/<path>/` altında yedekleniyor.
- [x] Faz 3: Uçtan uca senaryo testleri (`test.sh`, 40 test)
  - Smudge kapatılınca not korumasıyla ilgili 14 testin hepsi FAIL veriyor; testler gerçekten not kaybını yakalıyor.
- [ ] Faz 4 (gerekirse): `filter.process` ile hızlandırma
  - Ölçüm: dosya başına ~30 ms (Python başlatma süresi). 300 dosyalık `add` ya da checkout ≈ 9 sn.

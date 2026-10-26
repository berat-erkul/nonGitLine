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

## Nasıl çalışıyor

- **clean filter:** `git add` sırasında dosyayı notsuz hâle getirir ve index'e bu hâli gider. Diskteki dosyaya dokunulmaz.
- **smudge filter:** git dosyanın üzerine yazdığında (pull, merge, rebase, stash, checkout, reset) notları bağlam satırlarına göre geri yerleştirir. Yerleştiremediği notu silmez; **yetim** olarak `.git/nongitline/` içinde saklar ve uyarı basar.
- **pre-commit:** satır sonuna yazılmış ya da yanlış yazılmış işaretleri yakalar.
- **pre-push:** gönderilecek commit'lerde not kalmışsa push'u reddeder.

Ayarlar yereldir (`.git/config`, `.git/info/attributes`) ve commit'e girmez.

### Neden smudge şart: asıl tehlike `pull`

Clean filter kullanınca git, notlu dosyayı "değişmemiş" sayar, çünkü temiz hâli index'tekiyle aynıdır. Bu yüzden dosyanın üzerine sormadan yazar. `fetch` diske dokunmaz, güvenlidir. Ama upstream'in dokunduğu bir dosyada `pull` (merge ya da rebase), conflict, `stash`/`--autostash`, branch değiştirme ve `reset --hard` notları siler. Smudge bu silinmeyi telafi eder.

## Fazlar

- [ ] Faz 0: Kurulum ve git davranışlarının doğrulanması (spike)
- [ ] Faz 1: Clean, Java/C# lexer'ı, install, pre-commit/pre-push check, yedek
- [ ] Faz 2: Smudge, not anchoring, yetim yönetimi
- [ ] Faz 3: Uçtan uca senaryo testleri (`test.sh`)
- [ ] Faz 4 (gerekirse): `filter.process` ile hızlandırma

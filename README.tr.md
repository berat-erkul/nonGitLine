# nonGitLine

**Kişisel notlarını kaynak kodun içinde tut, ama hiçbir zaman commit'leme.**

Bir yorum satırını `//!!` ile başlatırsan o satır diskteki dosyanda kalır ama commit'e, push'a ve GitHub'a hiç girmez. Commit öncesinde ekstra bir adım yok; git'i her zamanki gibi kullanırsın.

```
Disk (yerel)                          Commit / GitHub
//!! gite gitmeyecek not              code1
code1                          →      code2
code2
```

Not satırı tamamen çıkarılır, yerine boş satır bırakılmaz. Diskteki dosyana dokunulmaz. Notlar `pull`, `rebase`, `stash`, `checkout` ve `reset --hard` sonrasında da yerinde kalır.

[English README](README.md) · [Tasarım notları (EN)](docs/DESIGN.md)

## Bu ne? Eklenti mi, uygulama mı?

İkisi de değil. Tek dosyalık bir komut satırı aracı. `nongitline install` onu git'in kendi mekanizmalarına bağlar: bir **filter** (clean/smudge) ve iki **hook** (pre-commit/pre-push). Ondan sonra git aracı kendisi çağırır; terminal, IntelliJ, Rider ya da VS Code fark etmez.

## Kurulum

Gerekenler: macOS ya da Linux, Python 3.9+, git 2.11+. Diller: Java ve C#.

**1. Aracı indir (makine başına bir kez):**

```bash
git clone https://github.com/berat-erkul/nonGitLine.git ~/tools/nonGitLine
mkdir -p ~/.local/bin
ln -s ~/tools/nonGitLine/nongitline ~/.local/bin/nongitline   # ~/.local/bin PATH'te olmalı
```

**2. Repoda aç (repo başına bir kez):**

```bash
cd ~/code/projem
nongitline install
nongitline status   # filter : on / hooks : pre-commit, pre-push / ide : off
```

`install` sadece `.git/` içine yazar: `.git/config`, `.git/info/attributes` ve hook'lar. Hiçbiri commit'e girmez; takım arkadaşların normal bir repo görür.

**3. İsteğe bağlı, VS Code:** bu adım olmadan editör notları değişiklik gibi gösterir; commit'ler yine doğrudur. `nongitline ide on` ile açılır, ayrıntısı aşağıdaki [Editör](#editör-vs-code) bölümünde.

**4. Günlük kullanım:** notu ayrı satıra `//!!` ile yaz, git'i her zamanki gibi kullan. Bir dosyanın commit'e giden hâlini görmek için: `git show :yol/Dosya.java`.

**5. Bir sorun olursa:** `nongitline ide off`, `nongitline off` ya da `nongitline uninstall`. Hiçbiri notlarını silmez.

## Not yazma kuralları

| Yazdığın | Sonuç |
| --- | --- |
| `//!! açıklama` (girintili de olabilir) | Diskte kalır, commit'e girmez |
| `int x = 5; //!! neden 5?` | Commit durur. Sadece tam satır notlar desteklenir. |
| `// !! yanlış yazım` | Commit durur, çünkü işaret yanlış yazılmış gibi görünüyor |
| Text block / `@"..."` içinde satır başında `//!!` | String verisi sayılır ve silinmez. Commit kontrol etmen için durur; bilerek yazdıysan `--no-verify` ile geçersin. |

## Not yerini bulamazsa: yetimler

Her not, altındaki ve üstündeki kod satırını hatırlar. Git dosyanın üzerine yazdığında not o satırların yanına geri konur. İkisi de silinmişse not tahminle bir yere yapıştırılmaz ve silinmez; **yetim** olarak saklanır ve uyarı basılır:

```bash
nongitline orphans                    # yetimleri listeler
nongitline orphans --drop A.java      # elle yerine koyduktan sonra unutturur
```

Ayrıca notlu her dosyanın son 20 sürümü `.git/nongitline/backup/` altında yedeklenir.

## Açma / kapama

Araç hem git'in hem editörün dosyalarını nasıl gördüğünü değiştiriyor. Bir şey ters giderse her parça tek komutla kapatılabilir. Kapatmak notları ya da not deposunu silmez; tekrar açınca kaldığı yerden devam eder.

```bash
nongitline status      # filter : on / hooks : pre-commit, pre-push / ide : off
nongitline off         # filtreyi kapat: notlar değişiklik olarak görünür, ama hook'lar commit'i yine engeller
nongitline on          # filtreyi aç (kapalıyken `git add` yaptıklarını tekrar `git add` et)
nongitline ide on      # editör yardımcılarını aç
nongitline ide off     # editör yardımcılarını kapat
```

## Editör (VS Code)

Editör notları iki yerde değişiklik gibi gösterir:

1. **Kenardaki yeşil çizgiler:** editör dosyanı commit'teki hâliyle karşılaştırır, orada not yoktur.
2. **Changes listesi:** not ekleyince dosya boyutu değişir. Git, boyut değişince içeriğe bakmadan dosyayı "değişti" sayar.

`nongitline ide on` (repo başına, varsayılan kapalı) ikisini de düzeltir:

- **Çizgiler:** git'in *textconv* özelliği kullanılır. VS Code commit'teki hâli `git show --textconv` ile okur; nonGitLine ona notları geri eklenmiş hâlini verir. Commit'in kendisi değişmez.
- **Liste:** `nongitline refresh`, notsuz içeriği index'tekiyle aynı olan dosyaları listeden düşürür. Hiçbir şeyi stage etmez. Kaydederken otomatik çalışması için VS Code'a [Run on Save](https://marketplace.visualstudio.com/items?itemName=emeraldwalk.RunOnSave) eklentisini kur ve kullanıcı ayarlarına İngilizce README'deki bloğu ekle.

`ide on` açıkken `git diff > x.patch` notları bağlam satırı olarak içerir ve başka yerde uygulanamaz. Patch için `git diff --no-textconv` ya da `git format-patch` kullan.

## Bilinen sınırlar

- Notlar sadece bu klasörün `.git/` dizininde yaşar. Yeni bir clone'da ya da başka makinede yoktur.
- Not ekleyip ya da silip `git add` yapmadan önce `git status` dosyayı ` M` gösterir ama diff boştur. Git'in kendi davranışı bu; `git add` ya da `nongitline refresh` (editörde kaydederken otomatik) düzeltir.
- Yerelde alınan `git archive` çıktısı notları içerir. GitHub'ın "Download ZIP" çıktısı temizdir. Notsuz yerel arşiv için:
  `git -c filter.nongitline.process= -c filter.nongitline.required=false archive HEAD -o proje.zip`
- Dosya yeniden adlandırılırsa (rename) notlar eski yolda kalır ve `orphans` listesinde görünür.
- Henüz test edilmedi: Windows, IDE'lerin seçili satırları commit etme özelliği (hook'lar yine de korur), `git worktree`, submodule, `cherry-pick`.

## Test

```bash
./test.sh   # 60 kontrol; Linux ve macOS'ta CI'da koşar
```

## Lisans

[MIT](LICENSE)

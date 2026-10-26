#!/bin/bash
# End-to-end checks for nongitline in throwaway repos. Usage: ./test.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
NGL="$HERE/nongitline"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export PATH="/usr/bin:$PATH"  # run on the system python3 (what IDEs launched from the Dock get)
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
FAILS=0
ok()   { echo "ok   $1"; }
fail() { echo "FAIL $1"; FAILS=$((FAILS + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

echo "== lexer"
python3 - "$NGL" <<'EOF' || FAILS=$((FAILS + 1))
import sys, importlib.machinery, importlib.util
loader = importlib.machinery.SourceFileLoader('ngl', sys.argv[1])
m = importlib.util.module_from_spec(importlib.util.spec_from_loader('ngl', loader)); loader.exec_module(m)
s, k = m.strip_notes, m.line_kinds
cases = [  # (source, is C#, expected committed content)
    ('//!! note\ncode1\ncode2\n', False, 'code1\ncode2\n'),
    ('code\n//!! x', False, 'code\n'),
    ('a\r\n  //!! x\r\nb\r\n', True, 'a\r\nb\r\n'),
    ('﻿//!! x\nclass A{}\n', False, '﻿class A{}\n'),
    ('String t = """\n//!! data\n""";\n//!! note\nx;\n', False, 'String t = """\n//!! data\n""";\nx;\n'),
    ('var v = @"line\n//!! data ""q""\n";\n//!! n\n', True, 'var v = @"line\n//!! data ""q""\n";\n'),
    ('var r = """\n//!! raw\n""";\n', True, 'var r = """\n//!! raw\n""";\n'),
    ('var r = $@"{x["k"]}\n//!! d\n";\n', True, 'var r = $@"{x["k"]}\n//!! d\n";\n'),
    ('/*\n//!! in comment\n*/\n', False, '/*\n*/\n'),
    ('/*\n//!! closes */\n', False, '/*\n//!! closes */\n'),
    ('String u = "http://!!";\n', False, 'String u = "http://!!";\n'),
    ("char q = '\"';\n//!! n\nx\n", False, "char q = '\"';\nx\n"),
]
bad = [(src, s(src, cs), exp) for src, cs, exp in cases if s(src, cs) != exp]
assert k(['int x = 5; //!! why\n'], False) == ['trailing']
assert k(['// !! typo\n'], False) == ['typo']
assert k(['String s = "a //!! b";\n'], False) == [None]
for b in bad:
    print('FAIL lexer', repr(b))
print('ok   lexer' if not bad else '')
sys.exit(1 if bad else 0)
EOF

echo "== git"
cd "$T"
git init -q --bare origin.git
git clone -q origin.git a 2>/dev/null
cd a
"$NGL" install >/dev/null

# 1. the example from the README
printf '//!! not\ncode1\ncode2\n' > A.java
git add A.java && git commit -qm one
check "commit holds 2 lines"     '[ "$(git show HEAD:A.java)" = "$(printf "code1\ncode2")" ]'
check "disk keeps the note"      '[ "$(head -1 A.java)" = "//!! not" ]'
check "status is clean"          '[ -z "$(git status --porcelain)" ]'
check "backup was taken"         '[ -n "$(ls .git/nongitline/backup/A.java)" ]'

# 2. partial staging: only the staged hunk goes in, the note never does
printf 'h1\n//!! n\nb\nc\nd\ne\nf\ng\nh\ni\nj\nk\nh2\n' > B.java
git add B.java && git commit -qm b
printf 'h1-new\n//!! n\nb\nc\nd\ne\nf\ng\nh\ni\nj\nk\nh2-new\n' > B.java
printf 'y\nn\n' | git add -p B.java >/dev/null 2>&1
git commit -qm partial
check "add -p: staged hunk in"     'git show HEAD:B.java | grep -qx h1-new'
check "add -p: unstaged hunk out"  'git show HEAD:B.java | grep -qx h2'
check "add -p: note out"           '! git show HEAD:B.java | grep -q "//!!"'
check "add -p: disk intact"        'grep -qx h2-new B.java && grep -qx "//!! n" B.java'
git commit -qam rest

# 9. trailing note blocks the commit
printf 'int x = 5; //!! why 5\n' > C.java
git add C.java
check "trailing note blocks commit" '! git commit -qm trailing 2>/dev/null'
check "mistyped marker blocks"     'printf "// !! typo\n" > C.java && git add C.java && ! git commit -qm typo 2>/dev/null'
git rm -qf --cached C.java && rm C.java

# 8. //!! inside a text block is data: kept, and the hooks ask for --no-verify
printf 'class S {\nString t = """\n//!! data\n""";\n}\n' > S.java
git add S.java
check "text block: stays in index"  'git show :S.java | grep -qx "//!! data"'
check "text block: commit asks"     '! git commit -qm s 2>/dev/null'
git commit -qm s --no-verify

# 10. bytes are preserved
printf 'a\r\n//!! x\r\nb\r\n' > crlf.cs
printf '\xef\xbb\xbf//!! x\nclass B {}\n' > bom.java
printf 'x\n//!! last' > noeol.java
git add crlf.cs bom.java noeol.java && git commit -qm bytes
check "CRLF kept"            '[ "$(git cat-file blob HEAD:crlf.cs | od -c | head -1)" = "$(printf "a\r\nb\r\n" | od -c | head -1)" ]'
check "BOM kept"             '[ "$(git cat-file blob HEAD:bom.java | head -c 3 | od -An -tx1 | tr -d " ")" = "efbbbf" ]'
check "no-EOL note dropped"  '[ "$(git cat-file blob HEAD:noeol.java | od -c)" = "$(printf "x\n" | od -c)" ]'
(echo '//!! big'; seq -f 'int b%g = 0; // padding to cross the 64 KB pkt-line limit' 1 8000) > Big.java
git add Big.java && git commit -qm big
check "big file split into packets" '[ "$(git show HEAD:Big.java)" = "$(sed 1d Big.java)" ]'

# 11. a crashing filter stops `git add`
git config filter.nongitline.process false
printf '//!! n2\ncode1\ncode2\nmore\n' > A.java
check "broken filter: add fails"    '! git add A.java 2>/dev/null'
check "broken filter: index intact" '! git show :A.java | grep -q more'
"$NGL" install >/dev/null
chmod 000 .git/nongitline/notes
check "unsavable note: add fails"   '! git add A.java 2>/dev/null'
check "unsavable note: index intact" '! git show :A.java | grep -q more'
chmod 755 .git/nongitline/notes

# 12. a note that slipped past the filter (hook skipped) is stopped at push
git push -q origin main --no-verify 2>/dev/null
git config --unset filter.nongitline.process; git config filter.nongitline.required false
git add A.java && git commit -qm leak --no-verify
"$NGL" install >/dev/null
check "leaked note blocks push"   '! git push -q origin main 2>/dev/null'
check "remote has no note"        '! git --git-dir=../origin.git show main:A.java | grep -q "//!!"'

echo "== pull / branch / stash (notes must survive anything that rewrites the file)"
cd "$T"
git init -q --bare o2.git
git clone -q o2.git me 2>/dev/null
git clone -q o2.git up 2>/dev/null
cd me && "$NGL" install >/dev/null
seq -f 'line%g' 1 12 > P.java
git add P.java && git commit -qm base && git push -q origin main
# the note sits above line5
sed -i '' 's|^line5$|//!! about line5\
line5|' P.java
git add P.java && git commit -qm note >/dev/null 2>&1  # nothing to commit: HEAD already equals the clean content
has_note() { grep -qx '//!! about line5' P.java; }
above5()   { [ "$(grep -A1 -x '//!! about line5' P.java | tail -1)" = line5 ]; }
upstream() { (cd "$T/up" && git pull -q origin main 2>/dev/null; eval "$1"; git commit -qam up && git push -q origin main); }

upstream "sed -i '' 's/^line11$/line11-up/' P.java"
git pull -q --no-rebase origin main 2>/dev/null
check "pull merge: note kept above line5" 'above5 && grep -qx line11-up P.java'
check "pull merge: status clean"          '[ -z "$(git status --porcelain)" ]'

upstream "sed -i '' 's/^line1$/line1-up/' P.java"
sed -i '' 's/^line12$/line12-me/' P.java && git commit -qam mine
git pull -q --rebase origin main 2>/dev/null
check "pull --rebase: note kept"          'above5 && grep -qx line1-up P.java && grep -qx line12-me P.java'
git push -q origin main

upstream "sed -i '' 's/^line2$/line2-up/' P.java"
sed -i '' 's/^line10$/line10-wip/' P.java
git pull -q --rebase --autostash origin main >/dev/null 2>&1
check "pull --autostash: note + wip kept" 'above5 && grep -qx line2-up P.java && grep -qx line10-wip P.java'
git checkout -q -- P.java

upstream "sed -i '' '/^line5$/d' P.java"
git pull -q --no-rebase origin main 2>/dev/null
check "next line deleted: note under prev" 'has_note && [ "$(grep -B1 -x "//!! about line5" P.java | head -1)" = line4 ]'

upstream "sed -i '' '/^line4$/d; /^line6$/d' P.java"
git pull -q --no-rebase origin main 2>"$T/err"
check "both neighbours gone: orphaned"    '! has_note && grep -q "could not be put back" "$T/err"'
check "orphans lists it"                  '"$NGL" orphans | grep -q "about line5"'
"$NGL" orphans --drop P.java >/dev/null
check "orphans --drop forgets it"         '! "$NGL" orphans | grep -q "about line5"'

sed -i '' 's|^line7$|//!! about line7\
line7|' P.java
upstream "sed -i '' 's/^line7$/line7-up/' P.java"
sed -i '' 's/^line7$/line7-me/' P.java && git commit -qam conflict
git pull -q --no-rebase origin main >/dev/null 2>&1
check "conflict: note kept or orphaned"   'grep -q "//!! about line7" P.java || "$NGL" orphans | grep -q "about line7"'
printf '%s\n' line1-up line2-up line3 '//!! about line7' line7-both line8 line9 line10 line11-up line12-me > P.java
git add P.java && git commit -qm merged && git push -q origin main
has7() { grep -qx '//!! about line7' P.java; }
check "conflict resolved: status clean"   'has7 && [ -z "$(git status --porcelain)" ]'

git checkout -q -b other && sed -i '' 's/^line9$/line9-other/' P.java && git commit -qam other
git checkout -q main
check "branch switch: note kept"          'has7 && grep -qx line9 P.java'
git checkout -q other
check "branch back: note kept"            'has7 && grep -qx line9-other P.java'
git checkout -q main
git rm -q P.java 2>/dev/null; git commit -qm gone; git checkout -q HEAD~1 -- P.java 2>/dev/null
check "file deleted then restored: note"  'has7'
git reset -q --hard HEAD~1
check "reset --hard: note kept"           'has7'
sed -i '' 's/^line3$/line3-wip/' P.java
git stash -q && check "stash: note kept"  'has7 && grep -qx line3 P.java'
git stash pop -q && check "stash pop: note + wip" 'has7 && grep -qx line3-wip P.java'
git checkout -q -- P.java
sed -i '' '/about line7/d' P.java && git add P.java  # size changed: git wants an add, as with any edit
git checkout -q other && git checkout -q main
check "deleted note stays deleted"        '! has7'
printf 'x\n//!! eof' > E.java && git add E.java && git commit -qm eof && git push -q origin main
upstream "printf 'top\n' | cat - E.java > t && mv t E.java && git add E.java"
git pull -q --no-rebase origin main 2>/dev/null
check "no-EOL last note: still last"      '[ "$(tail -1 E.java)" = "//!! eof" ] && head -1 E.java | grep -qx top'

"$NGL" uninstall >/dev/null
check "uninstall clears config"   '! git config --get-regexp "^filter\.nongitline" >/dev/null'
check "uninstall clears hooks"    '[ ! -e .git/hooks/pre-commit ] && [ ! -e .git/hooks/pre-push ]'

echo
[ "$FAILS" -eq 0 ] && echo "all passed" || { echo "$FAILS failed"; exit 1; }

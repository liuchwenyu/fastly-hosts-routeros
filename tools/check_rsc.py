#!/usr/bin/env python3
"""Conservative RouterOS source linter, NOT a RouterOS runtime or compiler.
Checks delimiters, strings, dangerous regressions, module size and helpers.
"""
from pathlib import Path
import re
import sys


# RouterOS menu properties become variables in find/print predicates. This is
# a source-level guard, not an interpreter. Use distinctive names on the RHS.
QUERY_PROPERTIES = {
    'name', 'type', 'comment', 'source', 'owner', 'script', 'address',
    'disabled', 'policy', 'host', 'contents', 'size', 'interval', 'status',
}

def mask_literals(text: str) -> str:
    """Mask comments/string literals while preserving newlines and code positions."""
    out=[]; quoted=False; escaped=False; comment=False
    for c in text:
        if c=='\n':
            out.append(c); comment=False
            if quoted and escaped: escaped=False
            continue
        if comment:
            out.append(' '); continue
        if quoted:
            out.append(' ')
            if escaped: escaped=False
            elif c=='\\': escaped=True
            elif c=='"': quoted=False
            continue
        if c=='#': comment=True; out.append(' ')
        elif c=='"': quoted=True; out.append(' ')
        else: out.append(c)
    return ''.join(out)

def query_shadow_issues(text: str) -> list[str]:
    issues=[]
    for lineno,line in enumerate(mask_literals(text).splitlines(),1):
        for query in re.finditer(r'\b(?:find\s+(?:where\s+)?|print\b[^\]\n]*?\bwhere\s+)([^\]\n]*)',line):
            for var in re.findall(r'\$([A-Za-z][A-Za-z0-9]*)\b',query.group(1)):
                if var in QUERY_PROPERTIES:
                    issues.append(f'line {lineno}: lookup variable ${var} collides with a RouterOS property')
    return issues

def lint(path: Path) -> list[str]:
    text = path.read_text(encoding='utf-8')
    errors: list[str] = []
    stack: list[tuple[str,int]] = []
    quote=False; comment=False; escape=False; line=1
    pairs={')':'(', ']':'[', '}':'{'}
    for c in text:
        if c=='\n':
            line+=1; comment=False
        if comment: continue
        if quote:
            if escape: escape=False
            elif c=='\\': escape=True
            elif c=='"': quote=False
            continue
        if c=='#': comment=True; continue
        if c=='"': quote=True; continue
        if c in '([{': stack.append((c,line))
        elif c in ')]}':
            if not stack or stack[-1][0]!=pairs[c]:
                errors.append(f'{path.name}:{line}: unmatched {c}')
            else: stack.pop()
    if quote: errors.append(f'{path.name}: unterminated string')
    for c,l in stack: errors.append(f'{path.name}:{l}: unmatched {c}')
    if len(text.encode()) > 57000: errors.append(f'{path.name}: source >57KB')
    if re.search(r'check-certificate\s*=\s*no\b',text): errors.append(f'{path.name}: TLS verification disabled')
    if re.search(r'\([ \t]*:to(str|num|ip|time)\b', text):errors.append(f'{path.name}: command inside () rather than []')
    if re.search(r'\(\$FHR\w+\s+\$',text):errors.append(f'{path.name}: function call inside () rather than []')
    if re.search(r':set\s+\w+\s+\(\$\w+,\s*\$(row|result|compact|old|sticky)\)',text):errors.append(f'{path.name}: map flattening append')
    if re.search(r'\b(TODO|FIXME|NotImplementedError)\b',text): errors.append(f'{path.name}: unfinished placeholder')
    errors.extend(f'{path.name}: {e}' for e in query_shadow_issues(text))
    return errors

def main() -> int:
    root=Path(__file__).resolve().parents[1]
    files=sorted((root/'routeros').glob('*.rsc'))
    errs=[e for p in files for e in lint(p)]
    combined='\n'.join(p.read_text(encoding='utf-8') for p in files)
    defs=set(re.findall(r':global\s+(FHR\w*)\s+do=',combined))
    calls=set(re.findall(r'\[\$(FHR\w*)\b',combined))
    for c in sorted(calls-defs):errs.append('unresolved function: '+c)
    print(f'Checked {len(files)} RouterOS source files; {len(defs)} functions.')
    for e in errs: print(e)
    if not errs: print('Static checks PASS. This is not RouterOS execution.')
    return bool(errs)
if __name__=='__main__': sys.exit(main())

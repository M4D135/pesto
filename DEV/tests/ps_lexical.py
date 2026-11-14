"""Conservative PowerShell lexical delimiter checker (not a semantic parser)."""
import re

_WORD_RE = re.compile(r'[\w:-]+')

def tokens(src):
    n=len(src); i=0
    def quoted(i,q):
        start=i; i+=1
        while i<n:
            if src[i]=='`' and q=='"': i+=2; continue
            if src[i]==q:
                if i+1<n and src[i+1]==q: i+=2; continue
                return i+1
            if q=='"' and src.startswith('$(',i):
                i=code(i+2,')',False)[0]; continue
            i+=1
        raise ValueError(f'Unclosed string offset {start}')
    out=[]
    def code(i,until=None,emit=True):
        stack=[]
        while i<n:
            c=src[i]
            if src.startswith('<#',i):
                end=src.find('#>',i+2)
                if end<0: raise ValueError('Unclosed block comment')
                i=end+2; continue
            if c=='#':
                end=src.find('\n',i); i=n if end<0 else end+1; continue
            if c=='`': i+=2; continue
            if c=='@' and i+1<n and src[i+1] in "'\"" and re.match(r'@['+"'\""+r'][ \t]*\r?\n',src[i:]):
                q=src[i+1]; m=re.search(r'^'+re.escape(q)+r'@',src[i+2:],re.M)
                if not m: raise ValueError(f'Unclosed here-string offset {i}')
                if emit: out.append(('here',i,i+2+m.end()))
                i=i+2+m.end(); continue
            if c in "'\"":
                j=quoted(i,c)
                if emit: out.append(('string',i,j))
                i=j; continue
            if c in '({[':
                stack.append((c,i))
                if emit: out.append((c,i,i+1))
            elif c in ')}]':
                if not stack and until==c: return i+1, out
                if not stack or {'(':')','{':'}','[':']'}[stack[-1][0]]!=c:
                    raise ValueError(f'Delimiter mismatch {c!r} offset {i}, stack={stack[-3:]}')
                stack.pop()
                if emit: out.append((c,i,i+1))
            elif emit and (c.isalpha() or c=='_'):
                m=_WORD_RE.match(src,i); j=m.end(); out.append(('word',i,j)); i=j; continue
            i+=1
        if stack or until: raise ValueError(f'Unclosed delimiters {stack[-3:]} until={until}')
        return i,out
    return code(0)[1]

def functions(src):
    tt=tokens(src); ret={}
    depth0=0
    for j,(kind,a,b) in enumerate(tt):
        if kind=='{': depth0+=1
        elif kind=='}': depth0-=1
        if depth0: continue
        if kind!='word' or src[a:b].lower()!='function': continue
        name=src[tt[j+1][1]:tt[j+1][2]]
        k=j+2
        while tt[k][0]!='{': k+=1
        depth=1; l=k+1
        while depth:
            depth+= (tt[l][0]=='{')-(tt[l][0]=='}'); l+=1
        if name in ret: raise ValueError('Duplicate function '+name)
        ret[name]=(a,tt[l-1][2])
    return ret


def smart_quote_hazards(src):
    """Find unescaped smart delimiters in ASCII-delimited PowerShell strings.

    PowerShell treats U+2018/U+2019 and U+201C/U+201D as quotation marks.
    Here-string text and comments are intentionally not rewritten. Nested $()
    expressions are inspected as code. This remains a lint rule, not a parser.
    Returns (offset, character) pairs; doubling that character preserves text.
    """
    n=len(src); found=[]
    singles="\u2018\u2019"; doubles="\u201c\u201d"
    def quoted(i,q):
        i+=1; smart=singles if q=="'" else doubles
        while i<n:
            c=src[i]
            if q=='"' and c=='`':i+=2;continue
            if c in smart:
                if i+1<n and src[i+1]==c:i+=2;continue
                found.append((i,c));i+=1;continue
            if c==q:
                if i+1<n and src[i+1]==q:i+=2;continue
                return i+1
            if q=='"' and src.startswith('$(',i):i=code(i+2,')');continue
            i+=1
        return i
    def code(i,end=None):
        while i<n:
            c=src[i]
            if end and c==end:return i+1
            if src.startswith('<#',i):
                j=src.find('#>',i+2);i=n if j<0 else j+2;continue
            if c=='#':
                j=src.find('\n',i);i=n if j<0 else j+1;continue
            if c=='`':i+=2;continue
            m=re.match(r'@([\'\"])[ \t]*\r?\n',src[i:])
            if m:
                q=m[1];j=i+m.end();terminator=re.search(r'^'+re.escape(q)+r'@',src[j:],re.M)
                stop=n if not terminator else j+terminator.start()
                if q=='"':
                    while j<stop:
                        if src[j]=='`':j+=2
                        elif src.startswith('$(',j):j=code(j+2,')')
                        else:j+=1
                i=n if not terminator else stop+2;continue
            if c in "'\"":i=quoted(i,c);continue
            if c in singles+doubles:found.append((i,c));i+=1;continue
            if c in '([{':i=code(i+1,{'(':')','[':']','{':'}'}[c]);continue
            i+=1
        return i
    code(0)
    return found

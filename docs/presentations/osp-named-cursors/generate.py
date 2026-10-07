"""Generate the English OSP design PDF with Matplotlib."""
from pathlib import Path
from html import escape

OUT = Path(__file__).parent

def code(s):
    return '<pre><code>' + escape(s) + '</code></pre>'

def box(title, body, color='blue'):
    return f'<div class="box {color}"><h3>{title}</h3>{body}</div>'

def cols(*items):
    return '<div class="cols">' + ''.join(items) + '</div>'

def chain(label, values, color):
    return f'<div class="chain {color}"><b>{label}</b>' + '<span class="arrow">→</span>'.join(f'<span class="node">{v}</span>' for v in values) + '</div>'

slides = [
('OSP: Joint Access to Multiple Nodes',
 '<p>Named cursors · Joint entry events · One integer per node</p>'
 + cols(box('Problem', '<p>A dot product reads two sequences together. An ordinary rhs reference hides the second traversal channel.</p>'), box('Solution', '<p>Declare a fixed set of named channels. Execute an ability only when all current nodes match its entry predicates.</p>'))
 + '<p>Current goal: correct execution on the Python CPU backend. GPU layout and address optimization are future work.</p>'),
('One Output, Two Input Paths',
 '<p>C[i,j] = Σ A[i,k] × B[k,j]</p>'
 + chain('A row i: ', [1,2,3], 'blue') + chain('B column j: ', [7,9,11], 'teal')
 + code('k=0: 1 × 7     k=1: 2 × 9     k=2: 3 × 11\nC[i,j] = 7 + 18 + 33 = 58')
 + '<p>Each step consumes a corresponding pair of nodes. Each input node stores one integer.</p>'),
('Existing Pattern: here Plus an rhs Reference',
 code('self.total += here.value * self.rhs.value;\nfollowing = [self.rhs->:ColumnNext:->];\nif following { self.rhs = following[0]; }\nvisit [->:RowNext:->];')
 + cols(box('Explicit primary traversal', '<p>The walker queue and visit manage the movement of here.</p>'), box('Secondary traversal in private state', '<p>The programmer maintains rhs and its pairing manually. The compiler must infer its access pattern.</p>'))
 + '<p>A regular column chain can be deterministic. This expression alone does not guarantee physical layout or fixed-stride addressing.</p>'),
('Make Both Positions First-Class Channels',
 code('walker Dot {\n    cursor a, b;\n    has total: int = 0;\n\n    can multiply with (a: Scalar entry, b: Scalar entry) {\n        self.total += here[a].value * here[b].value;\n        visit[a] [->:RowNext:->];\n        visit[b] [->:ColumnNext:->];\n    }\n}')
 + '<p>Cursor declarations are untyped. The programmer names the channels. Both entry predicates may match the same Scalar type.</p>'),
('One Joint Event, Two Independent Queues',
 cols(box('Channel a / RowNext', '<p>Current node: 1. Schedule successor: 2.</p>'), box('Channel b / ColumnNext', '<p>Current node: 7. Schedule successor: 9.</p>'))
 + code('Round 1: a=1, b=7 → multiply runs once\nBoth positions stay stable while abilities execute.\nvisit schedules arrivals; it does not move the current nodes.\nRound 2: a=2, b=9 → match the joint predicates again')
 + '<p>All predicates must match. multiply never observes one channel halfway through its advancement.</p>'),
('Preserve here; Define the New Event Contract',
 '<p>here[a] is channel a’s current node. Implicit edge origins inside visit[a] use that node. Legacy walkers keep their original execution path.</p>'
 + code('Round start:       consume one fresh arrival per channel\nMultiple targets:  FIFO pairing; no Cartesian product\nChannel exhausted: end traversal; discard unmatched tails\nNo visit:          consume queued siblings, or become exhausted\nOld entry:         never reused as a new arrival')
 + '<p>These are the choices recorded in the CPU design document. Joint entry is an arrival-event barrier, not repeated triggering on a held node.</p>'),
('CPU Matmul: Shared Scalar Nodes',
 code('node Scalar { has value: int; }\nedge RowNext {}\nedge ColumnNext {}\n\n# Launch one Dot for each C[i,j].\nw = Dot();\n{"a": A_row_head[i], "b": B_col_head[j]} spawn w;\n# Write w.total into the Scalar node for C[i,j].')
 + cols(box('Shared inputs', '<p>MK nodes for A and KN nodes for B. Output walkers share those inputs rather than copying each multiplication pair.</p>'), box('Independent results', '<p>MN scalar output nodes. Each output independently accumulates K products.</p>'))
 + '<p>Illustrative caller code. Graph construction, bindings and output writes stay on the host.</p>'),
('Predictable Traversal vs. Predictable Addresses',
 cols(box('What the semantics expose', '<p>Which nodes are accessed together, which relations advance them, and when the joint ability fires.</p>'), box('What layout optimization still needs', '<p>Shape, stride, regular adjacency, access permissions and a suitable physical representation.</p>'))
 + code('Candidate lowering for a regular row-major layout:\nA address = base_A + (i*K + k) × sizeof(int)\nB address = base_B + (k*N + j) × sizeof(int)')
 + '<p>CPU named cursors do not guarantee contiguous storage, cache hits or fixed latency. Arbitrary graph successors may still require edge-data loads.</p>'),
('Beyond Matmul: Joint Multi-Input Computation',
 code('Dot product / αx+y:  two input sequences, paired steps\nStrassen sums:       corresponding nodes of two quadrants\nStrassen recombine:  corresponding nodes of P1, P4, P5, P7\n\nC00 = P1 + P4 - P5 + P7')
 + '<p>Recursive task scheduling, dependencies and temporary storage remain separate concerns.</p>'
 + '<p>Sparse intersection needs one-sided advancement while retaining the other position. The current fresh-arrival contract cannot directly provide that behavior. Stencils also need boundary rules.</p>'),
('CPU Correctness First, Layout Optimization Next',
 cols(box('Implementation scope', '<p>Parser / AST / semantic checks</p><p>Python code generation and runtime</p><p>Dot product and scalar-node matmul</p><p>Boundary tests and legacy compatibility</p>'), box('Key validation cases', '<p>Same-type and heterogeneous matching</p><p>FIFO branches, empty and unequal queues</p><p>Stable current positions and correct outputs</p><p>Explicit rejection of unsupported combinations</p>'))
 + '<p>Design value: make joint access relationships explicit in OSP.</p>'
 + '<p>Sources: our design discussion, docs/design/named-cursors.md, and the dual-cursor example in graphs.jac. Implementation is in progress; this deck claims no completed test results.</p>')
]

from html.parser import HTMLParser
import re
import matplotlib.pyplot as plt
from matplotlib.backends.backend_pdf import PdfPages
from matplotlib.font_manager import FontProperties
import textwrap

class TextBlocks(HTMLParser):
    def __init__(self):
        super().__init__()
        self.parts = []
        self.in_code = False
    def handle_starttag(self, tag, attrs):
        if tag in ('p', 'h3', 'pre', 'tr', 'div'):
            self.parts.append('\n')
        if tag == 'pre':
            self.in_code = True
        if tag in ('td', 'th'):
            self.parts.append('  |  ')
    def handle_endtag(self, tag):
        if tag in ('p', 'h3', 'pre', 'tr', 'div'):
            self.parts.append('\n')
        if tag == 'pre':
            self.in_code = False
    def handle_data(self, data):
        self.parts.append(data)

def wrap_line(line, limit=105):
    return textwrap.wrap(line, width=limit, replace_whitespace=False, drop_whitespace=True) or ['']

font = FontProperties(fname='/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc')
destination = OUT / 'osp-named-cursors.pdf'
with PdfPages(destination, metadata={'Title': 'Jac OSP Named Cursors: Problem and Solution', 'Author': 'Jac design discussion'}) as pdf:
    for number, (title, content) in enumerate(slides, 1):
        parser = TextBlocks()
        parser.feed(content)
        raw = re.sub(r'\n[ \t]*\n+', '\n\n', ''.join(parser.parts)).strip()
        lines = []
        for line in raw.splitlines():
            lines.extend(wrap_line(line))
        fig = plt.figure(figsize=(16, 9), facecolor='#09111f')
        fig.text(.065, .91, f'JAC / OSP DESIGN · CPU FIRST · {number:02d}', color='#91afd4', fontsize=11)
        fig.text(.065, .82, title, fontproperties=font, fontsize=27, color='#f2f6ff')
        fig.add_artist(plt.Line2D([.065,.935],[.775,.775], color='#62d0b4', linewidth=2))
        spacing = min(.050, .64 / max(len(lines), 1))
        fontsize = min(18, max(11, spacing * 430))
        y = .73
        for line in lines:
            fig.text(.075, y, line, fontproperties=font, fontsize=fontsize, color='#dde8f7')
            y -= spacing
        fig.text(.065,.035,'CPU design proposal · GPU layout optimization is future work',fontproperties=font,fontsize=10,color='#91afd4')
        fig.text(.91,.035,f'{number} / {len(slides)}',fontsize=11,color='#91afd4')
        pdf.savefig(fig)
        plt.close(fig)
print(f'Generated {len(slides)} PDF slides: {destination}')

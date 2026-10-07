"""Build an English vector PDF from checked-in experimental evidence.

Run from any directory: python docs/presentations/jac-research-results/generate.py
Requires matplotlib; no network, HTML or GPU execution.
"""
from pathlib import Path
import json
import textwrap
import statistics
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.backends.backend_pdf import PdfPages
from matplotlib.patches import FancyBboxPatch

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).parent
BLUE, TEAL, ORANGE = '#2563eb', '#078477', '#c76b16'
INK, MUTED, BG = '#17243b', '#56647b', '#f5f7fb'
plt.rcParams.update({'font.family': 'DejaVu Sans', 'pdf.fonttype': 42})
def read(path):
    return json.loads((ROOT / path).read_text())

OLD = read('jac/examples/transformer_graph/results/benchmark_cuda.json')
OLDCPU = read('jac/examples/transformer_graph/results/benchmark_cpu.json')
NEW = read('jac/examples/transformer_dataflow/results/validation_cuda_0.json')
PLAN = read('jac/examples/transformer_dataflow/analysis.json')
FULL = read('scripts/gpu_walker/large_matmul/validation/full-run.json')
PROFILE = read('scripts/gpu_walker/large_matmul/validation/profile.json')
EVENT = read('scripts/gpu_walker/large_matmul/validation/ordinary.json')
SOURCES = [
 'jac/examples/transformer_graph/results/benchmark_cpu.json',
 'jac/examples/transformer_graph/results/benchmark_cuda.json',
 'jac/examples/transformer_dataflow/results/validation_cpu.json',
 'jac/examples/transformer_dataflow/results/validation_cuda_0.json',
 'jac/examples/transformer_dataflow/analysis.json',
 'scripts/gpu_walker/large_matmul/validation/full-run.json',
 'scripts/gpu_walker/large_matmul/validation/ordinary.json',
 'scripts/gpu_walker/large_matmul/validation/profile.json',
 'docs/design/gpu-cursor-concatenation-results.md',
 'docs/design/gpu-large-matmul-3000-results.md',
]

class Deck:
    def __init__(self, pdf): self.pdf, self.page = pdf, 0
    def slide(self, title, section, source, subtitle=''):
        self.page += 1
        self.fig = plt.figure(figsize=(16, 9), facecolor='white')
        self.ax = self.fig.add_axes([0, 0, 1, 1]); self.ax.set(xlim=(0,16), ylim=(0,9)); self.ax.axis('off')
        self.ax.text(.7,8.55,section.upper(),fontsize=12,color=TEAL,weight='bold')
        self.ax.text(.7,7.88,title,fontsize=29,color=INK,weight='bold')
        if subtitle: self.ax.text(.7,7.34,subtitle,fontsize=16,color=MUTED)
        self.ax.plot([.7,15.3],[.65,.65],color='#dce3ed',lw=1)
        self.ax.text(.7,.33,source,fontsize=9,color=MUTED)
        self.ax.text(15.3,.33,f'{self.page:02d}  |  2026-10-07',ha='right',fontsize=10,color=MUTED)
        return self.ax
    def text(self, text, x=.8, y=6.7, width=86, size=21, color=INK):
        lines=[]
        for para in text.split('\n'):
            lines.extend(textwrap.wrap(para,width=width) if para else [''])
        self.ax.text(x,y,'\n'.join(lines),va='top',fontsize=size,color=color,linespacing=1.5)
    def box(self,x,y,w,h,title,body,color=BLUE):
        self.ax.add_patch(FancyBboxPatch((x,y),w,h,boxstyle='round,pad=0.12',facecolor=BG,edgecolor='#dce3ed'))
        self.ax.text(x+.25,y+h-.45,title,fontsize=21,color=color,weight='bold',va='top')
        self.text(body,x+.25,y+h-1.03,width=max(20,int(w*6.1)),size=18)
    def table(self, headers, rows, widths=None, y=6.9, h=4.7, size=18):
        a=self.fig.add_axes([.05,(y-h)/9,.9,h/9]);a.axis('off')
        t=a.table(cellText=rows,colLabels=headers,colWidths=widths,cellLoc='left',colLoc='left',bbox=[0,0,1,1])
        t.auto_set_font_size(False);t.set_fontsize(size)
        for (r,c),cell in t.get_celld().items():
            cell.set_edgecolor('#dce3ed');cell.PAD=.12
            cell.set_facecolor('#edf2fa' if r==0 else ('white' if r%2 else BG))
            cell.get_text().set_color(INK)
            if r==0:cell.get_text().set_weight('bold')
    def bars(self,labels,values,unit='ms',pos=(.23,.24,.68,.48),colors=None):
        a=self.fig.add_axes(pos);a.barh(labels,values,color=colors or [BLUE,TEAL,ORANGE]);a.invert_yaxis()
        a.spines[['top','right','left']].set_visible(False);a.tick_params(axis='y',length=0,labelsize=18)
        a.tick_params(axis='x',labelsize=13);a.set_xlabel(unit,fontsize=16);a.set_xlim(0,max(values)*1.25)
        for i,v in enumerate(values):a.text(v+max(values)*.025,i,f'{v:.3f}',va='center',fontsize=18,color=INK)
    def finish(self): self.pdf.savefig(self.fig);plt.close(self.fig)

def old_case(data, dtype='float32'):
    return next(c for c in data['cases'] if c['config_name']=='medium' and c['dtype']==dtype)
def medians(data):
    c=old_case(data)
    return [c['graphs']['original']['methods'][k]['end_to_end']['median_ms'] for k in ('jac_graph','torch_eager','torch_compile')]
def kernel_medians(data, metric):
    return [statistics.median(r[metric] for r in data['records'] if r['layout']==label and r['phase']=='measured' and r['mode']=='resident')/1000 for label in ('Current','Predicted','Random')]

def actual_nodes(d, positions, title_prefix=''):
    """Draw only real exported nodes and direct edges; no invented dependencies."""
    for producer,consumer,port in PLAN['edges']:
        if producer in positions and consumer in positions:
            x,y=positions[producer];u,v=positions[consumer]
            dx,dy=u-x,v-y
            scale=min(1.06/abs(dx) if dx else float('inf'), .48/abs(dy) if dy else float('inf'))
            d.ax.annotate('',xy=(u-dx*scale,v-dy*scale),xytext=(x+dx*scale,y+dy*scale),arrowprops=dict(arrowstyle='->',color=MUTED,lw=1.5))
    for name,(x,y) in positions.items():
        label=name.removeprefix(title_prefix)
        typ=PLAN['node_types'][name];shape=PLAN['specs'][name]['shape']
        d.ax.add_patch(FancyBboxPatch((x-1.0,y-.42),2.0,.84,boxstyle='round,pad=.06',facecolor=BG,edgecolor=TEAL))
        d.ax.text(x,y,f'{label}\n{typ}  {shape}',ha='center',va='center',fontsize=11,color=INK)

def build():
    OUT.mkdir(parents=True,exist_ok=True)
    path=OUT/'jac-transformer-and-gpu-results.pdf'
    with PdfPages(path) as pdf:
        pdf.infodict().update(Title='Transformer on Jac and Jac on GPU: measured results',Author='Jac research experiments',Subject='Two research tracks, evidence and limitations')
        d=Deck(pdf)
        d.slide('Transformer on Jac + Jac on GPU','Research results','Evidence collected 2026-10-06 and 2026-10-07','Executable graphs, named cursors, physical layouts and measured outcomes')
        d.box(.8,2.3,6.8,4.2,'Part I: Transformer on Jac','Preserved module-level model.\nNew operation-level dataflow graph.\nCPU/CUDA correctness and analysis.',BLUE)
        d.box(8.2,2.3,7,4.2,'Part II: Jac on GPU','Named cursor execution.\nCorrected A-then-B BFS packing.\nFull 3000-cubed MatMul and profiling.',TEAL)
        d.finish()

        d.slide('Read the evidence at the right level','Research results','Repository reports and JSON listed on the final slide')
        d.table(['Claim','Evidence','Boundary'],[
          ['Transformer graph works','CPU/CUDA differential tests','Random weights; inference only'],
          ['New dataflow analysis works','Real graph edits + invalid graph tests','Concrete shapes; no alias analysis'],
          ['Random layout is slower at 3000³','Paired Nsight kernel measurements','Structured int64 fixture'],
          ['New BFS beats Current','Not established','Small differences change direction'],
          ['Cache/coalescing explains speed','Not established','Nsight Compute permission denied']],h=5.5,size=16)
        d.finish()

        d.slide('I. Transformer on Jac','Part I','jac/examples/transformer_graph/ and transformer_dataflow/','Two independent examples; the original 80 files remain unchanged')
        d.text('A graph should express executable dependencies, then support analysis.\n\nModule-level nodes explain the architecture. Operation-level nodes expose tensor producers, consumers and intermediate values.\n\nNeither representation alone proves an advantage over PyTorch FX / export.',width=86,size=24)
        d.finish()

        d.slide('The preserved module-level model','Part I','transformer_graph/README.md; model.jac')
        d.box(.8,2.0,6.8,4.7,'Graph and execution','18 computation nodes, 22 data edges.\nWeights belong to concrete module nodes.\nA host Jac walker schedules ready nodes.',BLUE)
        d.box(8.2,2.0,7,4.7,'Tensor CPU / CUDA path','PyTorch tensor primitives execute math.\nWeights and activations stay on device.\nEdges pass tensor references.\nNo per-module download or sync.',TEAL)
        d.text('One encoder + one decoder; post-norm, causal attention and cross-attention.',y=1.35,size=17)
        d.finish()

        d.slide('Existing Transformer: GPU latency baseline','Part I','transformer_graph/results/benchmark_cuda.json (2026-10-06)','Medium float32: d=256, heads=8, FF=1024, vocabulary=1024; lengths 128 / 96')
        d.bars(['Jac module graph','PyTorch eager','PyTorch compile'],medians(OLD),unit='Resident forward latency (ms), median of 36 requests')
        d.text('CPU medians: '+ ' / '.join(f'{v:.3f}' for v in medians(OLDCPU))+' ms in the same method order.',y=1.55,size=17)
        d.text('Equivalent weights and observables; no Jac speed advantage measured.',y=1.05,size=17,color=ORANGE)
        d.finish()

        d.slide('Profiling the preserved implementation','Part I','transformer_graph/results/benchmark_cuda.json; README.md','Independent profiling runs; these durations are not a decomposition of forward latency')
        prof=old_case(OLD)['graphs']['original']['profiles']
        rows=[]
        for label,k in [('Jac graph','jac_graph'),('Eager','torch_eager'),('Compile','torch_compile')]:
            p=prof[k];rows.append([label,f"{p['cuda_kernel_count']/p['calls']:.0f}",f"{p['kernel_sum_ms']/p['calls']:.4f}"])
        d.table(['Method','Kernels / request','Profile kernel sum / request (ms)'],rows,h=2.7,y=6.9,size=20)
        d.text('Jac and eager execute the same number of math kernels. Compile reduces kernel count.\nHost traversal / scheduling costs are observed in cProfile and handle-replay tests.\nProfile instrumentation and submission gaps prevent a strict causal subtraction.',y=3.6,width=96,size=19)
        d.finish()

        case=NEW['cases']['small_float64']
        d.slide('New example: operation-level dataflow','Part I','transformer_dataflow/model.jac; analysis.json')
        d.table(['Graph property','Measured / exported value'],[
            ['Nodes / tensor edges',f"{case['nodes']} / {case['edges']}"],
            ['Parameter nodes',str(case['parameters'])],
            ['Independently checked intermediates',str(case['checked_intermediates'])],
            ['Execution contract','Producer output -> named consumer port'],
            ['Analysis / execution','Separate Jac walkers']],h=4.8,widths=[.45,.55],size=20)
        d.text('Linear, Attention, FFN and LayerNorm are build-time expansions, not runtime black boxes.',y=1.35,size=17)
        d.finish()

        d.slide('Actual decoder attention: selected primitive nodes','Part I','transformer_dataflow/analysis.json; attention.dot / attention.svg','Direct edges only. Q/K/V projection subgraphs and some boundary inputs are omitted here.')
        positions={
          'dec_attn.q.heads':(1.9,6.2),'dec_attn.k.heads':(5.0,6.2),'dec_attn.k.transpose':(5.0,4.7),
          'dec_attn.score.matmul':(2.0,4.7),'dec_attn.score':(2.0,3.2),
          'dec_attn.mask':(5.0,3.2),'dec_attn.masked':(2.0,1.7),
          'dec_attn.probabilities':(8.0,1.7),'dec_attn.v.heads':(8.0,4.7),
          'dec_attn.context':(8.0,3.2),'dec_attn.context.transpose':(11.0,3.2),
          'dec_attn.context.contiguous':(11.0,4.7),'dec_attn.joined':(14.0,4.7),
          'dec_attn.output.matmul':(14.0,3.2),'dec_attn.output':(14.0,1.7)}
        actual_nodes(d,positions,'dec_attn.');d.finish()

        d.slide('Actual LayerNorm expansion','Part I','transformer_dataflow/analysis.json; norm.dot / norm.svg','Selected exported nodes and their direct dependencies; gamma / beta / epsilon are parameter or constant inputs')
        positions={
          'enc_norm1.residual':(2,6),'enc_norm1.mean':(5,6),'enc_norm1.center':(8,6),
          'enc_norm1.square':(11,6),'enc_norm1.variance':(14,6),
          'enc_norm1.stable':(14,3.8),'enc_norm1.rsqrt':(11,3.8),
          'enc_norm1.normalized':(8,3.8),'enc_norm1.scaled':(5,3.8),'enc_norm1':(2,3.8)}
        actual_nodes(d,positions,'enc_norm1.')
        d.text('Residual Add -> mean / centering -> variance -> inverse sqrt -> gamma / beta affine.',y=2.05,size=19)
        d.text('Shape and dtype labels come from the actual analysis, not a handwritten architecture diagram.',y=1.3,size=17,color=MUTED)
        d.finish()

        d.slide('What the analysis walker computes','Part I','transformer_dataflow/model.jac; numerics.py')
        d.table(['Analysis','Implementation / contract'],[
          ['Dependencies','Enumerate real edges; check port producers and roots'],
          ['Metadata propagation','Shape, dtype, device; meta tensor operation rules'],
          ['Topological order','Visit only after every input is ready'],
          ['Invalid graphs','Reject missing/duplicate inputs, cycles and bad shapes'],
          ['Plan invalidation','Fingerprint edges, attributes and parameter metadata'],
          ['Liveness','Compute last consumers; clear values after last use']],h=5.3,size=17,widths=[.3,.7])
        d.finish()

        d.slide('Correctness and graph mutation evidence','Part I','transformer_dataflow/results/validation_cpu.json; validation_cuda_0.json')
        max64=max(v['max_cpu_device_error'] for k,v in NEW['cases'].items() if k.endswith('float64'))
        max32=max(v['max_cpu_device_error'] for k,v in NEW['cases'].items() if k.endswith('float32'))
        d.text(f'8 CPU/CUDA cases: two configurations x two precisions x two devices.\n137 intermediate results checked against independent equations.\nMaximum CPU/CUDA difference: float64 {max64:.2e}; float32 {max32:.2e}.',size=22,width=92)
        d.box(.8,1.15,6.8,2.8,'Positive graph edits','Rewire a residual input.\nInsert Constant + Multiply in logits.\nThe execution walker stays unchanged.',BLUE)
        d.box(8.2,1.15,7,2.8,'Negative checks','Missing encoder-memory input.\n11 additional invalid graph cases.\nChanged shape / attributes invalidate plan.',TEAL)
        d.finish()

        d.slide('What is established; what remains open','Part I','transformer_dataflow/README.md; preservation.json')
        d.box(.8,1.7,6.8,5,'Established','Real primitive graph and parameter nodes.\nMetadata, topology and last-use analysis.\nCPU/CUDA execution and graph-edit tests.\nOriginal 80 files hash-preserved.',BLUE)
        d.box(8.2,1.7,7,5,'Not established','No new-model performance comparison.\nNo FX/export advantage demonstrated.\nNo fusion, symbolic shapes or training.\nLogical liveness bytes are not allocator memory; aliases are not analyzed.',ORANGE)
        d.finish()

        d.slide('II. Jac on GPU','Part II','docs/design/gpu-named-cursors.md','One integer per graph node; joint cursor arrival and predictable traversal structure')
        d.text('Independent FIFO per cursor and lane.\nA round consumes one fresh arrival from every cursor.\nCurrent positions remain stable during the joint ability.\nPacking changes storage indices, not execution events.\n\nA fixed number of cursors is declared at compile time; no special two-cursor ABI.',width=87,size=24)
        d.finish()

        d.slide('MatMul: two graph paths per output','Part II','jac/examples/gpu/named_cursors.jac; gpu_cursors.py')
        d.box(.8,2.25,6.8,4.25,'Cursor a: A row','A[i,0] -> A[i,1] -> ... -> A[i,K-1]\nFollow RowNext.\nShared by every output in row i.',BLUE)
        d.box(8.2,2.25,7,4.25,'Cursor b: B column','B[0,j] -> B[1,j] -> ... -> B[K-1,j]\nFollow ColumnNext.\nShared by every output in column j.',TEAL)
        d.text('One lane accumulates C[i,j] = sum over k of A[i,k] * B[k,j].',y=1.45,size=22)
        d.finish()

        d.slide('Corrected Predicted: all A, then all B','Part II','gpu_cursors.py: predict_layout; gpu-cursor-concatenation-results.md','Multi-source BFS per cursor; concatenate in declaration order; shared identities appear once')
        a=[f'A{i}{k}' for k in range(4) for i in range(4)]
        b=[f'B{k}{j}' for k in range(4) for j in range(4)]
        rows=[[str(i*4)+'-'+str(i*4+3),'  '.join(a[i*4:i*4+4])] for i in range(4)]
        rows += [[str(16+i*4)+'-'+str(19+i*4),'  '.join(b[i*4:i*4+4])] for i in range(4)]
        d.table(['Physical slots','Actual 4 x 4 Predicted identity order'],rows,widths=[.2,.8],h=5.45,size=19)
        d.text('The earlier rank-interleaved implementation was removed. Historical measurements are labelled.',y=1.02,size=16,color=MUTED)
        d.finish()

        d.slide('Smaller MatMul: no stable new BFS gain','Part II','docs/design/gpu-cursor-concatenation-results.md (2026-10-07)','Pure resident kernel duration from independent Nsight Systems replay')
        d.table(['M x K x N','Current (us)','Predicted (us)','Random (us)'],[
          ['16 x 32 x 24','47.297','47.329','44.400'],
          ['32 x 64 x 48','93.024','92.736','98.080'],
          ['64 x 128 x 64, first run','237.266','259.522','238.674']],h=3.2,size=19)
        d.text('Large-case controlled replay changed the ranking.\nDo not interpret a single median as a stable win or regression.\nEvery layout preserved exact integer outputs and traversal semantics.',y=3.15,size=21)
        d.finish()

        d.slide('Address sectors: theory is not hardware traffic','Part II','gpu-cursor-concatenation-results.md; analyze_layout_sectors.py','64 x 128 x 64; median distinct 32-byte sectors per logical warp load')
        d.table(['Logical load','Current','Predicted','Random 928'],[
          ['A value','1','1','1'],['B value','9','8','32'],
          ['B tag','9','8','32'],['B CSR begin / end','9','9','32'],['B CSR target','8','8','32']],h=4.1,size=19)
        d.text('Exact packed addresses, per load / warp / round. Assumed aligned arena.\nNo cache state, backend instruction optimization or actual transaction count.\nNsight Compute counters remain inaccessible: ERR_NVGPUCTRPERM.',y=2.3,size=19,color=ORANGE)
        d.finish()

        d.slide('Full 3000 x 3000 x 3000: actually executed','Part II','large_matmul/validation/full-run.json; gpu-large-matmul-3000-results.md')
        d.table(['Scale / resource','Measured fact'],[
          ['Real input graph','18,000,000 nodes; 17,994,000 edges'],
          ['Outputs / arithmetic','9,000,000 outputs; 27 billion MACs per layout'],
          ['Batching','32768 lanes; 275 launches per complete result'],
          ['Readonly resident graph','0.671 GiB; one upload per layout'],
          ['CPU graph build / peak RSS','140.80 s / 27.78 GiB full-run peak'],
          ['Complete validations','Current, Predicted, Random seeds 928 / 929 / 930']],h=5.3,size=17,widths=[.36,.64])
        d.finish()

        d.slide('Full-result validation: five matching outputs','Part II','large_matmul/validation/full-run.json','Structured int64 weights: A[i,k]=i+1 and B[k,j]=j+1')
        d.text('Independent exact oracle for every output: C[i,j] = 3000 * (i+1) * (j+1).\nAll five complete result files contain 9,000,000 outputs and share one SHA256.\nAll device status values were zero.\n\nOutput Scalar nodes are materialized per batch, saved and released. We do not retain nine million CPU output nodes at once.',size=23,width=91)
        d.text('These results do not represent arbitrary dense-data or floating-point GEMM performance.',y=1.3,size=18,color=ORANGE)
        d.finish()

        d.slide('3000-cubed: paired pure kernel measurements','Part II','large_matmul/validation/profile.json','Complete packed graph; each sample computes 32768 outputs, not the whole result')
        d.bars(['Current','Predicted','Random'],kernel_medians(PROFILE,'kernel_profiler_us'),unit='Nsight pure kernel duration (ms), median of 48 resident samples')
        d.text('Ordinary event medians: '+' / '.join(f'{v:.3f}' for v in kernel_medians(EVENT,'kernel_event_us'))+' ms.',y=1.55,size=18)
        d.text('Random is about 8x slower. Current and Predicted remain close; no stable BFS advantage.',y=1.05,size=17,color=ORANGE)
        d.finish()

        d.slide('Large-run cost and cleanup limitations','Part II','large_matmul/validation/full-run.json; termination.json; cleanup-perf-report.txt')
        rows=[]
        for x in FULL['layouts']:
            label=x['layout'].title()+(f" {x['seed']}" if 'seed' in x else '')
            rows.append([label,f"{x.get('pack_s',x.get('permutation_s')):.2f}",f"{x['execute_all_batches_wall_s']:.2f}"])
        d.table(['Layout','Pack / permutation wall (s)','Full execution + validation / save (s)'],rows,h=3.6,size=17,widths=[.2,.37,.43])
        d.text('Random reuses Current pack. CPU tests overlapped pack: resource facts, not isolated CPU baselines.\nAfter all outputs were saved, finalization GC continued; sampled hotspot was gc_collect_main.\nThat finished experiment was terminated (exit 143). This is not a natural-exit end-to-end benchmark.',y=2.8,width=115,size=17,color=ORANGE)
        d.finish()

        d.slide('Measurement environments and contracts','Both research tracks','benchmark_cuda.json; large_matmul/validation/environment.json')
        d.table(['Experiment','Environment','What was measured'],[
            ['Module Transformer','RTX 3090; driver 595.71.05\nPython 3.13.7; Torch 2.8.0','2026-10-06; float32 / float64\nHost-driven tensor inference'],
            ['Primitive Transformer','CPU and CUDA; Torch 2.8.0','Correctness and graph analysis\nNo new speed comparison'],
            ['Large Jac MatMul','RTX 3090; driver 580.65.06\nPython 3.12.11; LLVM 20.1.8','2026-10-07; structured int64\nGenerated Jac walker kernel'],
        ],widths=[.23,.39,.38],h=3.5,size=17)
        d.text('Compare methods within each experiment. Cross-date timings and tensor versus scalar\nworkloads do not establish a shared speed ranking.\nThe module compile benchmark uses fixed shapes and an existing persistent cache.\nPure kernel timings exclude graph construction, packing, transfers and host scheduling.',y=2.9,size=18,width=110)
        d.finish()

        d.slide('Conclusions supported by the current evidence','Both research tracks','Transformer and GPU reports linked below')
        d.text('Transformer: executable module and primitive graphs work on CPU/CUDA.\nDataflow metadata, graph edits and last-use analysis are validated.\nA speed or compiler-cost advantage over FX/export has not been demonstrated.\n\nJac GPU: complete A-then-B packing works, including a full 3000-cubed result.\nOrdered layouts beat random strongly at that scale. New BFS does not beat Current reliably.\nHardware counter permission is the remaining gap for a causal memory explanation.',size=22,width=94)
        d.finish()

        d.slide('Evidence and reproduction','Both research tracks','All sources are local repository files; raw GPU binary artifacts are retained on the measurement host')
        d.text('Transformer\n  jac/examples/transformer_graph/README.md\n  jac/examples/transformer_dataflow/README.md\n  Both results/ directories; new analysis.json and execution.json\n\nJac GPU\n  docs/design/gpu-cursor-concatenation-results.md\n  docs/design/gpu-large-matmul-3000-results.md\n  scripts/gpu_walker/large_matmul/validation/\n\nPDF generator and source manifest accompany this deck.',size=19,width=99)
        d.finish()
    (OUT/'sources.json').write_text(json.dumps({'sources':SOURCES,'page_count':d.page,'pdf':path.name},indent=2)+'\n')
    print(f'{path} ({d.page} pages)')

if __name__ == '__main__': build()

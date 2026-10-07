"""Independent equivalent PyTorch baseline ONLY; Jac inference never calls this.

Return every module output and attention map so eager/compiled have the same
observable intermediate lifetime as the Jac graph. No nn.Transformer, SDPA,
fused layer_norm or graph scheduling helpers are used.
"""
import math
import torch

NAMES = ('source', 'target', 'enc_embed', 'enc_pos', 'enc_attn', 'enc_norm1',
         'enc_ffn', 'enc_norm2', 'dec_embed', 'dec_pos', 'dec_attn', 'dec_norm1',
         'cross_attn', 'dec_norm2', 'dec_ffn', 'dec_norm3', 'projection', 'probabilities')


def position(length, dimension, device, dtype):
    positions = torch.arange(length, device=device, dtype=dtype).unsqueeze(1)
    channels = torch.arange(dimension, device=device, dtype=dtype)
    frequencies = torch.pow(10000.0, -2.0 * torch.floor(channels / 2.0) / dimension)
    angles = positions * frequencies
    return torch.where((channels.to(torch.int64) % 2 == 0).unsqueeze(0),
                       torch.sin(angles), torch.cos(angles))


def eager_forward(p, source, target, heads, enc_position, dec_position, mask, alternate):
    """Independent explicit pipeline: this is the comparison, not Jac execution."""
    dimension = p['enc_embed']['table'].shape[1]
    width = dimension // heads

    def attention(x, memory, name, causal=False):
        q = torch.matmul(x, p[name]['w_q']) + p[name]['b_q']
        k = torch.matmul(memory, p[name]['w_k']) + p[name]['b_k']
        v = torch.matmul(memory, p[name]['w_v']) + p[name]['b_v']
        q = q.reshape(q.shape[0], heads, width).transpose(0, 1)
        k = k.reshape(k.shape[0], heads, width).transpose(0, 1)
        v = v.reshape(v.shape[0], heads, width).transpose(0, 1)
        scores = torch.matmul(q, k.transpose(-2, -1)) / math.sqrt(width)
        if causal:
            scores = scores.masked_fill(mask, -math.inf)
        probabilities = torch.softmax(scores, dim=-1)
        context = torch.matmul(probabilities, v)
        joined = context.transpose(0, 1).contiguous().reshape(x.shape[0], dimension)
        return torch.matmul(joined, p[name]['w_o']) + p[name]['b_o'], probabilities

    def norm(main, skip, name):
        added = main + skip
        mean = added.mean(dim=-1, keepdim=True)
        centered = added - mean
        variance = centered.square().mean(dim=-1, keepdim=True)
        return centered * torch.rsqrt(variance + 1e-5) * p[name]['gamma'] + p[name]['beta']

    def feed_forward(x, name):
        hidden = torch.matmul(x, p[name]['w_up']) + p[name]['b_up']
        activated = torch.relu(hidden)
        return torch.matmul(activated, p[name]['w_down']) + p[name]['b_down']

    enc_embed = torch.index_select(p['enc_embed']['table'], 0, source) * math.sqrt(dimension)
    enc_pos = enc_embed + enc_position
    enc_attn, enc_map = attention(enc_pos, enc_pos, 'enc_attn')
    enc_norm1 = norm(enc_attn, enc_attn if alternate else enc_pos, 'enc_norm1')
    enc_ffn = feed_forward(enc_norm1, 'enc_ffn')
    enc_norm2 = norm(enc_ffn, enc_norm1, 'enc_norm2')
    dec_embed = torch.index_select(p['dec_embed']['table'], 0, target) * math.sqrt(dimension)
    dec_pos = dec_embed + dec_position
    dec_attn, dec_map = attention(dec_pos, dec_pos, 'dec_attn', True)
    dec_norm1 = norm(dec_attn, dec_pos, 'dec_norm1')
    cross_attn, cross_map = attention(dec_norm1, enc_norm2, 'cross_attn')
    dec_norm2 = norm(cross_attn, dec_norm1, 'dec_norm2')
    dec_ffn = feed_forward(dec_norm2, 'dec_ffn')
    dec_norm3 = norm(dec_ffn, dec_norm2, 'dec_norm3')
    projection = torch.matmul(dec_norm3, p['projection']['weight']) + p['projection']['bias']
    probabilities = torch.softmax(projection, dim=-1)
    return (source, target, enc_embed, enc_pos, enc_attn, enc_norm1, enc_ffn, enc_norm2,
            dec_embed, dec_pos, dec_attn, dec_norm1, cross_attn, dec_norm2, dec_ffn,
            dec_norm3, projection, probabilities, enc_map, dec_map, cross_map)


class Baseline:
    def __init__(self, params, heads, source, target, alternate=False):
        self.params = params
        self.heads = heads
        self.source, self.target = source, target
        self.alternate = alternate
        table = params['enc_embed']['table']
        self.enc_position = position(len(source), table.shape[1], table.device, table.dtype)
        self.dec_position = position(len(target), table.shape[1], table.device, table.dtype)
        self.mask = torch.ones((len(target), len(target)), dtype=torch.bool, device=table.device).triu(1)
        self.core = eager_forward
        self.last = None

    def __call__(self):
        self.last = self.core(self.params, self.source, self.target, self.heads,
                              self.enc_position, self.dec_position, self.mask, self.alternate)
        return self.last[17]

    def compile(self):
        self.core = torch.compile(eager_forward, fullgraph=True, dynamic=False,
                                  backend='inductor', options={'triton.cudagraphs': False})

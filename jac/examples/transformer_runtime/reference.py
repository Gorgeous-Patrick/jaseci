"""Independent PyTorch equations. No Jac graph, primitive executor or metadata helpers."""
import math
import torch


def forward(parameters, source, target, dimension, heads, alternate=False):
    p = parameters
    values = {}

    def save(name, value):
        values[name] = value
        return value

    def affine(x, prefix):
        mm = save(prefix + '.matmul', x @ p[prefix + '.weight'])
        return save(prefix, mm + p[prefix + '.bias'])

    def attention(x, memory, prefix, causal=False):
        width = dimension // heads
        projected = {}
        for letter, producer in [('q', x), ('k', memory), ('v', memory)]:
            raw = affine(producer, prefix + '.' + letter)
            shaped = save(prefix + '.' + letter + '.reshape', raw.reshape(-1, heads, width))
            projected[letter] = save(prefix + '.' + letter + '.heads', shaped.transpose(0, 1))
        key = save(prefix + '.k.transpose', projected['k'].transpose(-2, -1))
        raw_scores = save(prefix + '.score.matmul', projected['q'] @ key)
        scores = save(prefix + '.score', raw_scores * (1 / math.sqrt(width)))
        if causal:
            mask = torch.ones((target.numel(), target.numel()), device=target.device, dtype=torch.bool).triu(1)
            save(prefix + '.mask', mask)
            scores = save(prefix + '.masked', scores.masked_fill(mask, -math.inf))
        probabilities = save(prefix + '.probabilities', torch.softmax(scores, dim=-1))
        context = save(prefix + '.context', probabilities @ projected['v'])
        transposed = save(prefix + '.context.transpose', context.transpose(0, 1))
        contiguous = save(prefix + '.context.contiguous', transposed.contiguous())
        joined = save(prefix + '.joined', contiguous.reshape(-1, dimension))
        return affine(joined, prefix + '.output')

    def norm(main, skip, prefix):
        added = save(prefix + '.residual', main + skip)
        mean = save(prefix + '.mean', added.mean(dim=-1, keepdim=True))
        center = save(prefix + '.center', added - mean)
        square = save(prefix + '.square', center.square())
        variance = save(prefix + '.variance', square.mean(dim=-1, keepdim=True))
        stable = save(prefix + '.stable', variance + 1e-5)
        inv = save(prefix + '.rsqrt', torch.rsqrt(stable))
        normalized = save(prefix + '.normalized', center * inv)
        scaled = save(prefix + '.scaled', normalized * p[prefix + '.gamma'])
        return save(prefix, scaled + p[prefix + '.beta'])

    def ffn(x, prefix):
        hidden = affine(x, prefix + '.up')
        relu = save(prefix + '.relu', torch.relu(hidden))
        return affine(relu, prefix + '.output')

    def embed(tokens, prefix):
        selected = save(prefix + '.gather', torch.index_select(p[prefix + '.table'], 0, tokens))
        return save(prefix, selected * math.sqrt(dimension))

    def positions(length):
        # Independent table equation, not model constants or numerics.position_table.
        rows = torch.arange(length, device=source.device, dtype=p['enc_embed.table'].dtype).unsqueeze(1)
        cols = torch.arange(dimension, device=source.device, dtype=rows.dtype)
        theta = rows * torch.pow(10000.0, -2 * torch.floor(cols / 2) / dimension)
        return torch.where((cols.to(torch.int64) % 2 == 0).unsqueeze(0), torch.sin(theta), torch.cos(theta))

    enc_embed = embed(source, 'enc_embed')
    enc_pos = save('enc_pos', enc_embed + positions(source.numel()))
    enc_attn = attention(enc_pos, enc_pos, 'enc_attn')
    enc_norm1 = norm(enc_attn, enc_attn if alternate else enc_pos, 'enc_norm1')
    enc_ffn = ffn(enc_norm1, 'enc_ffn')
    memory = norm(enc_ffn, enc_norm1, 'enc_norm2')
    dec_embed = embed(target, 'dec_embed')
    dec_pos = save('dec_pos', dec_embed + positions(target.numel()))
    dec_attn = attention(dec_pos, dec_pos, 'dec_attn', True)
    dec_norm1 = norm(dec_attn, dec_pos, 'dec_norm1')
    cross = attention(dec_norm1, memory, 'cross_attn')
    dec_norm2 = norm(cross, dec_norm1, 'dec_norm2')
    dec_ffn = ffn(dec_norm2, 'dec_ffn')
    dec_norm3 = norm(dec_ffn, dec_norm2, 'dec_norm3')
    projection = affine(dec_norm3, 'projection')
    save('probabilities', torch.softmax(projection, dim=-1))
    return values

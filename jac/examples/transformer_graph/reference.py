"""Independent direct CPU reference, used only for validation, never inference.

Uses separate numerical routines and a conventional explicit forward pipeline.
Parameters are deep snapshots read from concrete Jac node fields. This file
does not import the implementation's primitives or call any node methods.
"""
import math
from copy import deepcopy
from typing import Any


def forward(params, source, target, heads=2) -> dict[str, Any]:
    p = deepcopy(params)
    d = len(p['enc_embed']['table'][0])
    states = {}

    def affine(x, weight, bias):
        columns = list(zip(*weight))
        return [[math.fsum(a * b for a, b in zip(row, col)) + offset
                 for col, offset in zip(columns, bias)] for row in x]

    def embed(tokens, name):
        return [[v * d ** 0.5 for v in p[name]['table'][t]] for t in tokens]

    def pos(x):
        y = deepcopy(x)
        for t in range(len(y)):
            for i in range(d):
                angle = t * 10000 ** (-(i - i % 2) / d)
                y[t][i] += math.cos(angle) if i % 2 else math.sin(angle)
        return y

    def normalize(a, b, name):
        out = []
        for t in range(len(a)):
            row = [a[t][i] + b[t][i] for i in range(d)]
            mean = math.fsum(row) / d
            variance = math.fsum((v - mean) ** 2 for v in row) / d
            out.append([p[name]['gamma'][i] * (row[i] - mean)
                        * (variance + 1e-5) ** -0.5 + p[name]['beta'][i]
                        for i in range(d)])
        return out

    def attend(x, memory, name, causal=False):
        q, k, v = [affine(data, p[name]['w_' + which], p[name]['b_' + which]) for data, which in
                   ((x, 'q'), (memory, 'k'), (memory, 'v'))]
        width = d // heads
        out = [[0.0] * d for _ in x]
        for t in range(len(x)):
            for h in range(heads):
                indexes = range(h * width, (h + 1) * width)
                allowed = range(t + 1) if causal else range(len(memory))
                scores = [math.fsum(q[t][i] * k[s][i] for i in indexes)
                          * width ** -0.5 for s in allowed]
                exp = [math.exp(s - max(scores)) for s in scores]
                probs = [s / math.fsum(exp) for s in exp]
                for i in indexes:
                    out[t][i] = math.fsum(probs[s] * v[s][i] for s in allowed)
        return affine(out, p[name]['w_o'], p[name]['b_o'])

    def ffn(x, name):
        return affine([[max(v, 0) for v in row] for row in affine(x, p[name]['w_up'], p[name]['b_up'])],
                      p[name]['w_down'], p[name]['b_down'])

    def save(name, value):
        states[name] = value
        return value

    save('source', list(source))
    save('target', list(target))
    e = save('enc_embed', embed(source, 'enc_embed'))
    e = save('enc_pos', pos(e))
    a = save('enc_attn', attend(e, e, 'enc_attn'))
    e = save('enc_norm1', normalize(a, e, 'enc_norm1'))
    a = save('enc_ffn', ffn(e, 'enc_ffn'))
    memory = save('enc_norm2', normalize(a, e, 'enc_norm2'))
    x = save('dec_embed', embed(target, 'dec_embed'))
    x = save('dec_pos', pos(x))
    a = save('dec_attn', attend(x, x, 'dec_attn', True))
    x = save('dec_norm1', normalize(a, x, 'dec_norm1'))
    a = save('cross_attn', attend(x, memory, 'cross_attn'))
    x = save('dec_norm2', normalize(a, x, 'dec_norm2'))
    a = save('dec_ffn', ffn(x, 'dec_ffn'))
    x = save('dec_norm3', normalize(a, x, 'dec_norm3'))
    logits = save('projection', affine(x, p['projection']['weight'], p['projection']['bias']))
    probs = []
    for row in logits:
        exp = [math.exp(v - max(row)) for v in row]
        probs.append([v / math.fsum(exp) for v in exp])
    save('probabilities', probs)
    return states

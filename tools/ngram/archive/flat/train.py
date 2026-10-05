"""Offline multinomial logistic regression; only train/dev participate in selection."""
import hashlib
import json
import re
import struct
from pathlib import Path
import numpy as np
import sklearn
from sklearn.feature_extraction.text import CountVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score, classification_report, f1_score

ROOT = Path(__file__).resolve().parents[4]
HERE = ROOT / 'tools/ngram'

def normalize(text):
    # Explicit codepoint rules shared with NgramClassifier.normalize (no locale).
    chars = []
    for ch in text[:2048]:
        c = ord(ch)
        if 0xff01 <= c <= 0xff5e:
            c -= 0xfee0
        if 65 <= c <= 90:
            c += 32
        if 97 <= c <= 122 or 0x3400 <= c <= 0x9fff:
            chars.append(chr(c))
        else:
            chars.append(' ')
    return re.sub(' +', ' ', ''.join(chars)).strip()

def load(name):
    return [json.loads(line) for line in (HERE / 'data' / name).read_text(encoding='utf-8').splitlines()]

def main():
    train, dev = load('ngram_train_v2.jsonl'), load('ngram_dev_v2.jsonl')
    assert not ({x['splitGroup'] for x in train} & {x['splitGroup'] for x in dev})
    texts = [normalize(x['text']) for x in train]
    test = [normalize(x['text']) for x in dev]
    y, yt = [x['semanticKey'] for x in train], [x['semanticKey'] for x in dev]
    trials, best = [], None
    for grams in [(2, 3), (2, 4)]:
        for dim in [8192, 16384]:
            vec = CountVectorizer(analyzer='char', ngram_range=grams, max_features=dim, binary=True, lowercase=False, min_df=2, dtype=np.float64)
            x, xd = vec.fit_transform(texts), vec.transform(test)
            for c in [0.5, 2.0]:
                model = LogisticRegression(C=c, solver='saga', max_iter=180, tol=0.002, random_state=17, n_jobs=1).fit(x, y)
                scale = np.maximum(np.abs(model.coef_).max(axis=1), 1e-12) / 127
                q = np.rint(model.coef_ / scale[:, None]).astype(np.int8)
                logits = xd @ (q * scale[:, None]).T + model.intercept_
                probs = np.exp(logits - logits.max(axis=1)[:, None]); probs /= probs.sum(axis=1)[:, None]
                probs[np.asarray(xd.getnnz(axis=1)) == 0] = 0
                pred = model.classes_[probs.argmax(axis=1)]
                trial = dict(grams=grams, dimension=len(vec.vocabulary_), C=c, accuracy=accuracy_score(yt, pred), macroF1=f1_score(yt, pred, average='macro'), iterations=int(model.n_iter_.max()))
                trials.append(trial); print(json.dumps(trial), flush=True)
                if best is None or trial['macroF1'] > best[0]['macroF1']:
                    best = trial, vec, model, q, scale, probs, pred
    config, vec, model, q, scale, probs, pred = best
    threshold_trials = []
    top = probs.max(axis=1); margin = np.sort(probs, axis=1)[:, -1] - np.sort(probs, axis=1)[:, -2]
    for threshold in [.45, .60, .75, .85]:
        accepted = (top >= threshold) & (margin >= .15)
        threshold_trials.append(dict(threshold=threshold, coverage=float(accepted.mean()), accuracy=float(np.mean(pred[accepted] == np.array(yt)[accepted]))))
    eligible = [t for t in threshold_trials if t['accuracy'] >= .95]
    threshold = max(eligible, key=lambda t: t['coverage'])['threshold'] if eligible else .85
    vocab = vec.get_feature_names_out().tolist()
    header = dict(version=1, normalization='ascii-cjk-space-v1', grams=list(config['grams']), labels=model.classes_.tolist(), vocabulary=vocab, scales=scale.tolist(), bias=model.intercept_.tolist(), threshold=threshold, margin=.15)
    raw = json.dumps(header, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
    asset = b'LLNG' + struct.pack('<I', len(raw)) + raw + q.T.copy().tobytes()
    target = ROOT / 'assets/knowledge/ngram.bin'; target.write_bytes(asset)
    assert len(asset) <= 4 * 1024 * 1024
    report = dict(train=len(train), dev=len(dev), sklearn=sklearn.__version__, numpy=np.__version__, selection='highest dev macro F1, first configuration on ties; quantized inference', trials=trials, selected=config, thresholds=threshold_trials, threshold=threshold, assetBytes=len(asset), assetSha256=hashlib.sha256(asset).hexdigest(), perClass=classification_report(yt, pred, output_dict=True), macroAccuracy=float(np.mean([v['recall'] for k,v in classification_report(yt,pred,output_dict=True).items() if k in model.classes_])), dataSha256={name: hashlib.sha256((HERE/'data'/name).read_bytes()).hexdigest() for name in ['ngram_train_v2.jsonl','ngram_dev_v2.jsonl']})
    (HERE/'training_report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    vectors = [dict(text=t, normalized=normalize(t), scores=p.tolist()) for t,p in zip([d['text'] for d in dev[:12]], probs[:12])]
    for t in ['', '123 ! 🐈', 'ＡＢＣ１２３，🐈']:
        extra = vec.transform([normalize(t)])
        z = extra @ (q * scale[:, None]).T + model.intercept_
        p = np.exp(z - z.max()); p /= p.sum()
        if extra.nnz == 0:
            p[:] = 0
        vectors.append(dict(text=t, normalized=normalize(t), scores=p[0].tolist()))
    (HERE/'parity_vectors.json').write_text(json.dumps(vectors, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    (HERE/'dev_predictions.json').write_text(json.dumps([dict(id=row['id'], label=str(label), probability=float(p.max())) for row,label,p in zip(dev,pred,probs)], ensure_ascii=False, separators=(',', ':'))+'\n', encoding='utf-8')

if __name__ == '__main__':
    main()

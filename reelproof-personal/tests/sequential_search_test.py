"""Sequential retrieval ranking/coverage tests; no model credentials required."""
from pathlib import Path
import sys
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'backend'))
from sequential_search import sequential_top_k
rng=np.random.default_rng(73)
matrix=rng.normal(size=(366,768)).astype(np.float32)
matrix/=np.linalg.norm(matrix,axis=1,keepdims=True)
for query in [matrix[0],matrix[183],matrix[-1],rng.normal(size=768)]:
 normalized=np.asarray(query,dtype=np.float32);normalized/=np.linalg.norm(normalized)
 scores=matrix@normalized
 for top_k in [1,4,400]:
  for threshold in [None,0.0,0.2,1.01]:
   expected=[i for i in sorted(range(len(matrix)),key=lambda i:(-float(scores[i]),i)) if threshold is None or scores[i]>=threshold][:top_k]
   actual=sequential_top_k(query,matrix,top_k,threshold)
   assert [i for i,_ in actual]==expected
   assert all(abs(score-float(scores[i]))<1e-6 for i,score in actual)
# A strong hit at the last row must be found, not lost after an earlier match.
assert sequential_top_k([1,0],np.array([[.8,.6],[.6,.8],[1,0]],dtype=np.float32),1)==[(2,1.0)]
assert [i for i,_ in sequential_top_k([1,0],np.array([[1,0],[1,0],[1,0]],dtype=np.float32),2)]==[0,1]
assert sequential_top_k([1,0],np.empty((0,2),dtype=np.float32))==[]
assert sequential_top_k([1,0],np.array([[np.nan,0],[1,0]],dtype=np.float32))==[(1,1.0)]
for query in [[0,0],[np.nan,1],[1,2,3]]:
 try:sequential_top_k(query,np.array([[1,0]],dtype=np.float32))
 except ValueError:pass
 else:raise AssertionError('Invalid embeddings must fail explicitly')
print('PASS sequential scan: exhaustive-ranking equivalence, final-row hit, stable ties, threshold, empty corpus and invalid embeddings. No speed/accuracy claim.')

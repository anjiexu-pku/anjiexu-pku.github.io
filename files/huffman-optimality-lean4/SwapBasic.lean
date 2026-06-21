import CfProofs.Greedy.Huffman.Base
open HuffTree

lemma rootFreq_swapLeaves_eq (a b : ℕ) (t : HuffTree) : rootFreq (swapLeaves a b t) = rootFreq t := by
  induction t with
  | htLeaf s f =>
    by_cases hsa : s = a
    · rw [hsa]; simp [swapLeaves, rootFreq]
    · by_cases hsb : s = b
      · rw [hsb]; by_cases hba : b = a
        · rw [hba]; simp [swapLeaves, rootFreq]
        · simp [swapLeaves, rootFreq, hba]
      · simp [swapLeaves, rootFreq, hsa, hsb]
  | htInner l r ihl ihr => simp [swapLeaves, rootFreq, ihl, ihr]

lemma cost_swapLeaves_eq (a b : ℕ) (t : HuffTree) : cost (swapLeaves a b t) = cost t := by
  induction t with
  | htLeaf s f =>
    by_cases hsa : s = a
    · rw [hsa]; simp [swapLeaves, cost]
    · by_cases hsb : s = b
      · rw [hsb]; by_cases hba : b = a
        · rw [hba]; simp [swapLeaves, cost]
        · simp [swapLeaves, cost, hba]
      · simp [swapLeaves, cost, hsa, hsb]
  | htInner l r ihl ihr =>
    have hrfl := rootFreq_swapLeaves_eq a b l
    have hrfr := rootFreq_swapLeaves_eq a b r
    simp [swapLeaves, cost, ihl, ihr, hrfl, hrfr]

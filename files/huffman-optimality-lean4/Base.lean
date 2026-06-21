import Mathlib
/-!
# Huffman Coding — Optimal Prefix Code in Lean 4
Multi-agent formal verification (CLRS Ch. 16.3).
-/
open List

inductive HuffTree : Type
  | htLeaf (symbol freq : ℕ) | htInner (left right : HuffTree)
  deriving Repr, DecidableEq
open HuffTree

def rootFreq : HuffTree → ℕ
  | htLeaf _ f => f | htInner l r => rootFreq l + rootFreq r
def alphabet : HuffTree → Finset ℕ
  | htLeaf s _ => {s} | htInner l r => alphabet l ∪ alphabet r
def consistent : HuffTree → Prop
  | htLeaf _ _ => True
  | htInner l r => consistent l ∧ consistent r ∧ Disjoint (alphabet l) (alphabet r)
def height : HuffTree → ℕ
  | htLeaf _ _ => 0 | htInner l r => max (height l) (height r) + 1
def depthOf (s : ℕ) : HuffTree → Option ℕ
  | htLeaf sym _ => if sym = s then some 0 else none
  | htInner l r =>
    match depthOf s l with
    | some d => some (d + 1)
    | none => match depthOf s r with | some d => some (d + 1) | none => none
def freqOf (s : ℕ) : HuffTree → ℕ
  | htLeaf sym f => if sym = s then f else 0
  | htInner l r => freqOf s l + freqOf s r
def cost : HuffTree → ℕ
  | htLeaf _ _ => 0 | htInner l r => cost l + cost r + rootFreq l + rootFreq r
def nodeCount : HuffTree → ℕ
  | htLeaf _ _ => 1
  | htInner l r => 1 + nodeCount l + nodeCount r

lemma height_eq_zero_iff (t : HuffTree) : height t = 0 ↔ ∃ s f, t = htLeaf s f := by
  constructor
  · intro h; cases t with
    | htLeaf s f => exact ⟨s, f, rfl⟩
    | htInner l r => simp [height] at h
  · rintro ⟨s, f, rfl⟩; rfl
def sameFreqs (t u : HuffTree) : Prop := ∀ s, freqOf s t = freqOf s u
def optimum (t : HuffTree) : Prop :=
  consistent t ∧ (∀ s ∈ alphabet t, freqOf s t > 0) ∧ ∀ u, consistent u → sameFreqs t u → cost t ≤ cost u
def unite (t₁ t₂ : HuffTree) : HuffTree := htInner t₁ t₂
def insortTree (t : HuffTree) : List HuffTree → List HuffTree
  | [] => [t]
  | u :: us => if rootFreq t ≤ rootFreq u then t :: u :: us else u :: insortTree t us
def huffman : List HuffTree → HuffTree
  | [] => htLeaf 0 0 | [t] => t
  | t₁ :: t₂ :: rest => huffman (insortTree (unite t₁ t₂) rest)
termination_by forest => forest.length
decreasing_by
  simp_wf
  have hlen : (insortTree (unite t₁ t₂) rest).length = rest.length + 1 := by
    induction rest with
    | nil => simp [insortTree]
    | cons u us ih => simp [insortTree]; split <;> simp [ih, add_comm, add_left_comm]
  omega
def forest_consistent : List HuffTree → Prop
  | [] => True | [t] => consistent t
  | t :: ts => consistent t ∧ forest_consistent ts ∧ (∀ u ∈ ts, Disjoint (alphabet t) (alphabet u))
def forest_sorted : List HuffTree → Prop
  | [] => True | [_] => True
  | t₁ :: t₂ :: ts => rootFreq t₁ ≤ rootFreq t₂ ∧ forest_sorted (t₂ :: ts)
def replaceFreq (sym newFreq : ℕ) : HuffTree → HuffTree
  | htLeaf s f => if s = sym then htLeaf s newFreq else htLeaf s f
  | htInner l r => htInner (replaceFreq sym newFreq l) (replaceFreq sym newFreq r)
def swapFreqs (a c : ℕ) (t : HuffTree) : HuffTree :=
  replaceFreq c (freqOf a t) (replaceFreq a (freqOf c t) t)
def splitLeaf (t : HuffTree) (z a b fa fb : ℕ) : HuffTree :=
  match t with
  | htLeaf sym f => if sym = z then htInner (htLeaf a fa) (htLeaf b fb) else htLeaf sym f
  | htInner l r => htInner (splitLeaf l z a b fa fb) (splitLeaf r z a b fa fb)
def swapLeaves (a b : ℕ) : HuffTree → HuffTree
  | htLeaf s f => if s = a then htLeaf b f else if s = b then htLeaf a f else htLeaf s f
  | htInner l r => htInner (swapLeaves a b l) (swapLeaves a b r)
def mergePair (a b z fz : ℕ) : HuffTree → HuffTree
  | htInner (htLeaf x fx) (htLeaf y fy) =>
    if (x = a ∧ y = b) ∨ (x = b ∧ y = a) then htLeaf z fz
    else htInner (htLeaf x fx) (htLeaf y fy)
  | htInner l r => htInner (mergePair a b z fz l) (mergePair a b z fz r)
  | t => t

lemma nodeCount_swapLeaves_eq (a b : ℕ) (t : HuffTree) : nodeCount (swapLeaves a b t) = nodeCount t := by
  induction t with
  | htLeaf s f => unfold swapLeaves; simp [nodeCount]; split_ifs <;> simp [nodeCount]
  | htInner l r ihl ihr => unfold swapLeaves; simp [nodeCount, ihl, ihr]

lemma nodeCount_replaceFreq_eq (sym f : ℕ) (t : HuffTree) : nodeCount (replaceFreq sym f t) = nodeCount t := by
  induction t with
  | htLeaf s f' => unfold replaceFreq; simp [nodeCount]; split_ifs <;> simp [nodeCount]
  | htInner l r ihl ihr => unfold replaceFreq; simp [nodeCount, ihl, ihr]

-- Trivial
theorem rootFreq_nonneg (t : HuffTree) : rootFreq t ≥ 0 := by
  induction t with | htLeaf _ _ => omega | htInner _ _ ihl ihr => rw [rootFreq]; omega
theorem cost_nonneg (t : HuffTree) : cost t ≥ 0 := by
  induction t with | htLeaf _ _ => simp [cost] | htInner _ _ ihl ihr => rw [cost]; omega

-- Layer A lemmas

theorem freqOf_eq_zero_of_not_mem (s : ℕ) (t : HuffTree) (h : s ∉ alphabet t) : freqOf s t = 0 := by
  induction t with
  | htLeaf sym f =>
    have hs : sym ≠ s := by intro heq; subst heq; exact h (by simp [alphabet])
    simp [freqOf, hs]
  | htInner l r ihl ihr =>
    have hl : s ∉ alphabet l := by intro hm; apply h; simp [alphabet, hm]
    have hr : s ∉ alphabet r := by intro hm; apply h; simp [alphabet, hm]
    simp [freqOf, ihl hl, ihr hr]


theorem depthOf_none_of_not_mem (s : ℕ) (t : HuffTree) (h : s ∉ alphabet t) : depthOf s t = none := by
  induction t with
  | htLeaf sym f =>
    have hs : sym ≠ s := by intro heq; subst heq; exact h (by simp [alphabet])
    simp [depthOf, hs]
  | htInner l r ihl ihr =>
    have hl : s ∉ alphabet l := by intro hm; apply h; simp [alphabet, hm]
    have hr : s ∉ alphabet r := by intro hm; apply h; simp [alphabet, hm]
    simp [depthOf, ihl hl, ihr hr]

theorem depthOf_some_of_mem (s : ℕ) (t : HuffTree) (h : s ∈ alphabet t) : ∃ d, depthOf s t = some d := by
  induction t with
  | htLeaf sym f => simp [alphabet] at h; subst h; exact ⟨0, by simp [depthOf]⟩
  | htInner l r ihl ihr =>
    have h_union : s ∈ alphabet l ∪ alphabet r := by simpa [alphabet] using h
    rcases Finset.mem_union.1 h_union with (hl | hr)
    · rcases ihl hl with ⟨d, hd⟩; refine ⟨d + 1, ?_⟩; rw [depthOf]; simp [hd]
    · by_cases hl' : s ∈ alphabet l
      · rcases ihl hl' with ⟨d, hd⟩; refine ⟨d + 1, ?_⟩; rw [depthOf]; simp [hd]
      · have h_none_l : depthOf s l = none := depthOf_none_of_not_mem s l hl'
        rcases ihr hr with ⟨d, hd⟩
        refine ⟨d + 1, ?_⟩; rw [depthOf]; simp [h_none_l, hd]

theorem alphabet_replaceFreq (sym newFreq : ℕ) (t : HuffTree) :
    alphabet (replaceFreq sym newFreq t) = alphabet t := by
  induction t with
  | htLeaf s f => unfold replaceFreq; split <;> simp [alphabet]
  | htInner l r ihl ihr => simp [replaceFreq, alphabet, ihl, ihr]

theorem consistent_replaceFreq (sym newFreq : ℕ) (t : HuffTree) (h_cons : consistent t) :
    consistent (replaceFreq sym newFreq t) := by
  induction t with
  | htLeaf s f => unfold replaceFreq; split <;> simp [consistent]
  | htInner l r ihl ihr =>
    rcases h_cons with ⟨hcl, hcr, hd⟩
    rw [replaceFreq, consistent]
    refine ⟨ihl hcl, ihr hcr, ?_⟩
    rw [alphabet_replaceFreq sym newFreq l, alphabet_replaceFreq sym newFreq r]
    exact hd

theorem freqOf_replaceFreq_of_ne (sym newFreq other : ℕ) (t : HuffTree) (h_ne : other ≠ sym) :
    freqOf other (replaceFreq sym newFreq t) = freqOf other t := by
  induction t with
  | htLeaf s f =>
    by_cases h_eq : s = sym
    · subst h_eq; simp [replaceFreq, freqOf, Ne.symm h_ne]
    · simp [replaceFreq, freqOf, h_eq]
  | htInner l r ihl ihr => simp [replaceFreq, freqOf, ihl, ihr]

private lemma rootFreq_replaceFreq_id_of_not_mem (sym newFreq : ℕ) (t : HuffTree) (h : sym ∉ alphabet t) :
    rootFreq (replaceFreq sym newFreq t) = rootFreq t := by
  induction t with
  | htLeaf s f =>
    have hs : s ≠ sym := by intro heq; subst heq; exact h (by simp [alphabet])
    simp [replaceFreq, rootFreq, hs]
  | htInner l r ihl ihr =>
    have hl : sym ∉ alphabet l := by intro hm; apply h; simp [alphabet, hm]
    have hr : sym ∉ alphabet r := by intro hm; apply h; simp [alphabet, hm]
    simp [replaceFreq, rootFreq, ihl hl, ihr hr]

private lemma cost_replaceFreq_id_of_not_mem (sym newFreq : ℕ) (t : HuffTree) (h : sym ∉ alphabet t) :
    cost (replaceFreq sym newFreq t) = cost t := by
  induction t with
  | htLeaf s f =>
    have hs : s ≠ sym := by intro heq; subst heq; exact h (by simp [alphabet])
    simp [replaceFreq, cost, hs]
  | htInner l r ihl ihr =>
    have hl : sym ∉ alphabet l := by intro hm; apply h; simp [alphabet, hm]
    have hr : sym ∉ alphabet r := by intro hm; apply h; simp [alphabet, hm]
    have h_root_l : rootFreq (replaceFreq sym newFreq l) = rootFreq l :=
      rootFreq_replaceFreq_id_of_not_mem sym newFreq l hl
    have h_root_r : rootFreq (replaceFreq sym newFreq r) = rootFreq r :=
      rootFreq_replaceFreq_id_of_not_mem sym newFreq r hr
    simp [replaceFreq, cost, ihl hl, ihr hr, h_root_l, h_root_r]

theorem rootFreq_replaceFreq_eq_int (sym newFreq : ℕ) (t : HuffTree) (h_cons : consistent t)
    (h_sym_in : sym ∈ alphabet t) :
    (rootFreq (replaceFreq sym newFreq t) : ℤ) = (rootFreq t : ℤ) + ((newFreq : ℤ) - (freqOf sym t : ℤ)) := by
  induction t with
  | htLeaf s f => simp [alphabet] at h_sym_in; subst h_sym_in; simp [replaceFreq, rootFreq, freqOf]
  | htInner l r ihl ihr =>
    rcases h_cons with ⟨hcl, hcr, hd⟩
    have h_union : sym ∈ alphabet l ∪ alphabet r := by simpa [alphabet] using h_sym_in
    rcases Finset.mem_union.1 h_union with (hl_in | hr_in)
    · have hr_not : sym ∉ alphabet r := by
        have h_empty := Finset.disjoint_iff_inter_eq_empty.mp hd
        intro hmem
        have h_mem_inter : sym ∈ alphabet l ∩ alphabet r := Finset.mem_inter.mpr ⟨hl_in, hmem⟩
        rw [h_empty] at h_mem_inter; simp at h_mem_inter
      have h_freq_r : freqOf sym r = 0 := freqOf_eq_zero_of_not_mem sym r hr_not
      have h_root_r : rootFreq (replaceFreq sym newFreq r) = rootFreq r :=
        rootFreq_replaceFreq_id_of_not_mem sym newFreq r hr_not
      have h_ih := ihl hcl hl_in
      simp [replaceFreq, rootFreq, freqOf, h_freq_r, h_root_r, h_ih]; ring
    · have hl_not : sym ∉ alphabet l := by
        have h_empty := Finset.disjoint_iff_inter_eq_empty.mp hd
        intro hmem
        have h_mem_inter : sym ∈ alphabet l ∩ alphabet r := Finset.mem_inter.mpr ⟨hmem, hr_in⟩
        rw [h_empty] at h_mem_inter; simp at h_mem_inter
      have h_freq_l : freqOf sym l = 0 := freqOf_eq_zero_of_not_mem sym l hl_not
      have h_root_l : rootFreq (replaceFreq sym newFreq l) = rootFreq l :=
        rootFreq_replaceFreq_id_of_not_mem sym newFreq l hl_not
      have h_ih := ihr hcr hr_in
      simp [replaceFreq, rootFreq, freqOf, h_freq_l, h_root_l, h_ih]; ring

theorem cost_replaceFreq_eq (sym newFreq : ℕ) (t : HuffTree) (h_cons : consistent t) :
    (cost (replaceFreq sym newFreq t) : ℤ) = (cost t : ℤ) +
    ((newFreq : ℤ) - (freqOf sym t : ℤ)) * ((depthOf sym t).getD 0 : ℤ) := by
  induction t with
  | htLeaf s f =>
    by_cases h_eq : s = sym
    · subst h_eq; simp [replaceFreq, cost, freqOf, depthOf]
    · simp [replaceFreq, cost, freqOf, depthOf, h_eq]
  | htInner l r ihl ihr =>
    rcases h_cons with ⟨hcl, hcr, hd⟩
    have h_disjoint := Finset.disjoint_iff_inter_eq_empty.mp hd
    by_cases h_sym_l : sym ∈ alphabet l
    · have h_sym_not_r : sym ∉ alphabet r := by
        intro hm
        have h_mem_inter : sym ∈ alphabet l ∩ alphabet r := Finset.mem_inter.mpr ⟨h_sym_l, hm⟩
        rw [h_disjoint] at h_mem_inter; simp at h_mem_inter
      have h_freq_r : freqOf sym r = 0 := freqOf_eq_zero_of_not_mem sym r h_sym_not_r
      have h_depth_r : depthOf sym r = none := depthOf_none_of_not_mem sym r h_sym_not_r
      rcases depthOf_some_of_mem sym l h_sym_l with ⟨dl, h_depth_l⟩
      have h_root_l := rootFreq_replaceFreq_eq_int sym newFreq l hcl h_sym_l
      have h_cost_r_id : cost (replaceFreq sym newFreq r) = cost r :=
        cost_replaceFreq_id_of_not_mem sym newFreq r h_sym_not_r
      have h_root_r_id : rootFreq (replaceFreq sym newFreq r) = rootFreq r :=
        rootFreq_replaceFreq_id_of_not_mem sym newFreq r h_sym_not_r
      have h_ih := ihl hcl
      simp [replaceFreq, cost, rootFreq, freqOf, depthOf,
        h_freq_r, h_depth_r, h_depth_l, h_cost_r_id, h_root_r_id, h_ih, h_root_l]; ring
    · by_cases h_sym_r : sym ∈ alphabet r
      · have h_sym_not_l : sym ∉ alphabet l := h_sym_l
        have h_freq_l : freqOf sym l = 0 := freqOf_eq_zero_of_not_mem sym l h_sym_not_l
        have h_depth_l : depthOf sym l = none := depthOf_none_of_not_mem sym l h_sym_not_l
        rcases depthOf_some_of_mem sym r h_sym_r with ⟨dr, h_depth_r⟩
        have h_root_r := rootFreq_replaceFreq_eq_int sym newFreq r hcr h_sym_r
        have h_cost_l_id : cost (replaceFreq sym newFreq l) = cost l :=
          cost_replaceFreq_id_of_not_mem sym newFreq l h_sym_not_l
        have h_root_l_id : rootFreq (replaceFreq sym newFreq l) = rootFreq l :=
          rootFreq_replaceFreq_id_of_not_mem sym newFreq l h_sym_not_l
        have h_ih := ihr hcr
        simp [replaceFreq, cost, rootFreq, freqOf, depthOf,
          h_freq_l, h_depth_l, h_depth_r, h_cost_l_id, h_root_l_id, h_ih, h_root_r]; ring
      · have h_freq_l : freqOf sym l = 0 := freqOf_eq_zero_of_not_mem sym l h_sym_l
        have h_freq_r : freqOf sym r = 0 := freqOf_eq_zero_of_not_mem sym r h_sym_r
        have h_depth_l : depthOf sym l = none := depthOf_none_of_not_mem sym l h_sym_l
        have h_depth_r : depthOf sym r = none := depthOf_none_of_not_mem sym r h_sym_r
        have h_cost_l : cost (replaceFreq sym newFreq l) = cost l :=
          cost_replaceFreq_id_of_not_mem sym newFreq l h_sym_l
        have h_cost_r : cost (replaceFreq sym newFreq r) = cost r :=
          cost_replaceFreq_id_of_not_mem sym newFreq r h_sym_r
        have h_root_l : rootFreq (replaceFreq sym newFreq l) = rootFreq l :=
          rootFreq_replaceFreq_id_of_not_mem sym newFreq l h_sym_l
        have h_root_r : rootFreq (replaceFreq sym newFreq r) = rootFreq r :=
          rootFreq_replaceFreq_id_of_not_mem sym newFreq r h_sym_r
        simp [replaceFreq, cost, rootFreq, freqOf, depthOf,
          h_freq_l, h_freq_r, h_depth_l, h_depth_r, h_cost_l, h_cost_r, h_root_l, h_root_r]

-- Layer B: Exchange lemma

private lemma depthOf_replaceFreq_of_ne (sym newFreq other : ℕ) (t : HuffTree) (h_ne : other ≠ sym) :
    depthOf other (replaceFreq sym newFreq t) = depthOf other t := by
  induction t with
  | htLeaf s f => unfold replaceFreq; split <;> simp [depthOf, h_ne]
  | htInner l r ihl ihr => simp [replaceFreq, depthOf, ihl, ihr]

theorem cost_swapFreqs_le (t : HuffTree) (a c : ℕ)
    (h_cons : consistent t)
    (h_freq : freqOf a t ≤ freqOf c t)
    (h_depth : (depthOf a t).getD 0 ≤ (depthOf c t).getD 0)
    (h_ne : a ≠ c) :
    cost (swapFreqs a c t) ≤ cost t := by
  have ha_ne_c_sym : c ≠ a := Ne.symm h_ne
  have h_cons' : consistent (replaceFreq a (freqOf c t) t) :=
    consistent_replaceFreq a (freqOf c t) t h_cons
  have h_freq_c_unchanged : freqOf c (replaceFreq a (freqOf c t) t) = freqOf c t :=
    freqOf_replaceFreq_of_ne a (freqOf c t) c t ha_ne_c_sym
  have h_depth_c_unchanged : depthOf c (replaceFreq a (freqOf c t) t) = depthOf c t :=
    depthOf_replaceFreq_of_ne a (freqOf c t) c t ha_ne_c_sym
  have h1 := cost_replaceFreq_eq a (freqOf c t) t h_cons
  have h2 := cost_replaceFreq_eq c (freqOf a t) (replaceFreq a (freqOf c t) t) h_cons'
  have h_cost_int : (cost (swapFreqs a c t) : ℤ) ≤ (cost t : ℤ) := by
    rw [swapFreqs, h2, h_freq_c_unchanged, h_depth_c_unchanged, h1]
    have h_nonneg : 0 ≤ (freqOf c t : ℤ) - (freqOf a t : ℤ) := by omega
    have h_nonpos : ((depthOf a t).getD 0 : ℤ) - ((depthOf c t).getD 0 : ℤ) ≤ 0 := by omega
    nlinarith
  exact_mod_cast h_cost_int

-- Layer B: splitLeaf infrastructure

lemma splitLeaf_eq_of_z_not_mem (t : HuffTree) (z a b fa fb : ℕ) (h : z ∉ alphabet t) :
    splitLeaf t z a b fa fb = t := by
  induction t with
  | htLeaf sym f =>
    have hs : sym ≠ z := by intro heq; subst heq; exact h (by simp [alphabet])
    simp [splitLeaf, hs]
  | htInner l r ihl ihr =>
    have hl : z ∉ alphabet l := by intro hm; apply h; simp [alphabet, hm]
    have hr : z ∉ alphabet r := by intro hm; apply h; simp [alphabet, hm]
    simp [splitLeaf, ihl hl, ihr hr]

theorem rootFreq_splitLeaf_eq (t : HuffTree) (z a b fa fb : ℕ) (h_cons : consistent t)
    (h_z_in : z ∈ alphabet t) (h_sum : freqOf z t = fa + fb) :
    rootFreq (splitLeaf t z a b fa fb) = rootFreq t := by
  induction t with
  | htLeaf sym f =>
    simp [alphabet] at h_z_in; subst h_z_in
    have hf : f = fa + fb := by simp [freqOf] at h_sum; omega
    simp [splitLeaf, rootFreq, hf]
  | htInner l r ihl ihr =>
    rcases h_cons with ⟨hcl, hcr, hd⟩
    have h_disjoint := Finset.disjoint_iff_inter_eq_empty.mp hd
    have h_union : z ∈ alphabet l ∪ alphabet r := by simpa [alphabet] using h_z_in
    rcases Finset.mem_union.1 h_union with (hl_in | hr_in)
    · have hr_not : z ∉ alphabet r := by
        intro hm; have hm_inter := Finset.mem_inter.mpr ⟨hl_in, hm⟩
        rw [h_disjoint] at hm_inter; simp at hm_inter
      have h_freq_r : freqOf z r = 0 := freqOf_eq_zero_of_not_mem z r hr_not
      have h_sum_l : freqOf z l = fa + fb := by
        simp [freqOf] at h_sum; rw [h_freq_r] at h_sum; omega
      have h_split_r : splitLeaf r z a b fa fb = r :=
        splitLeaf_eq_of_z_not_mem r z a b fa fb hr_not
      have h_ih := ihl hcl hl_in h_sum_l
      simp [splitLeaf, rootFreq, h_split_r, h_ih]
    · have hl_not : z ∉ alphabet l := by
        intro hm; have hm_inter := Finset.mem_inter.mpr ⟨hm, hr_in⟩
        rw [h_disjoint] at hm_inter; simp at hm_inter
      have h_freq_l : freqOf z l = 0 := freqOf_eq_zero_of_not_mem z l hl_not
      have h_sum_r : freqOf z r = fa + fb := by
        simp [freqOf] at h_sum; rw [h_freq_l] at h_sum; omega
      have h_split_l : splitLeaf l z a b fa fb = l :=
        splitLeaf_eq_of_z_not_mem l z a b fa fb hl_not
      have h_ih := ihr hcr hr_in h_sum_r
      simp [splitLeaf, rootFreq, h_split_l, h_ih]

theorem cost_splitLeaf_eq (t : HuffTree) (z a b fa fb : ℕ) (h_cons : consistent t)
    (h_z_in : z ∈ alphabet t) (h_sum : freqOf z t = fa + fb) :
    cost (splitLeaf t z a b fa fb) = cost t + fa + fb := by
  have rootFreq_splitLeaf_eq' : ∀ (t' : HuffTree), consistent t' → z ∈ alphabet t' →
      freqOf z t' = fa + fb → rootFreq (splitLeaf t' z a b fa fb) = rootFreq t' := by
    intro t' hc hzin hs
    induction t' with
    | htLeaf sym f =>
      simp [alphabet] at hzin; subst hzin
      have hf : f = fa + fb := by simp [freqOf] at hs; omega
      simp [splitLeaf, rootFreq, hf]
    | htInner l r ihl ihr =>
      rcases hc with ⟨hcl, hcr, hd⟩
      have h_disjoint := Finset.disjoint_iff_inter_eq_empty.mp hd
      have h_union : z ∈ alphabet l ∪ alphabet r := by simpa [alphabet] using hzin
      rcases Finset.mem_union.1 h_union with (hl_in | hr_in)
      · have hr_not : z ∉ alphabet r := by
          intro hm
          have hm_inter := Finset.mem_inter.mpr ⟨hl_in, hm⟩
          rw [h_disjoint] at hm_inter; simp at hm_inter
        have h_freq_r : freqOf z r = 0 := freqOf_eq_zero_of_not_mem z r hr_not
        have h_sum_l : freqOf z l = fa + fb := by
          simp [freqOf] at hs; rw [h_freq_r] at hs; omega
        have h_split_r : splitLeaf r z a b fa fb = r :=
          splitLeaf_eq_of_z_not_mem r z a b fa fb hr_not
        have h_ih := ihl hcl hl_in h_sum_l
        simp [splitLeaf, rootFreq, h_split_r, h_ih]
      · have hl_not : z ∉ alphabet l := by
          intro hm
          have hm_inter := Finset.mem_inter.mpr ⟨hm, hr_in⟩
          rw [h_disjoint] at hm_inter; simp at hm_inter
        have h_freq_l : freqOf z l = 0 := freqOf_eq_zero_of_not_mem z l hl_not
        have h_sum_r : freqOf z r = fa + fb := by
          simp [freqOf] at hs; rw [h_freq_l] at hs; omega
        have h_split_l : splitLeaf l z a b fa fb = l :=
          splitLeaf_eq_of_z_not_mem l z a b fa fb hl_not
        have h_ih := ihr hcr hr_in h_sum_r
        simp [splitLeaf, rootFreq, h_split_l, h_ih]
  induction t with
  | htLeaf sym f =>
    simp [alphabet] at h_z_in; subst h_z_in
    have hf : f = fa + fb := by simp [freqOf] at h_sum; omega
    simp [splitLeaf, cost, rootFreq, hf]
  | htInner l r ihl ihr =>
    rcases h_cons with ⟨hcl, hcr, hd⟩
    have h_disjoint := Finset.disjoint_iff_inter_eq_empty.mp hd
    have h_union : z ∈ alphabet l ∪ alphabet r := by simpa [alphabet] using h_z_in
    rcases Finset.mem_union.1 h_union with (hl_in | hr_in)
    · have hr_not : z ∉ alphabet r := by
        intro hm
        have hm_inter := Finset.mem_inter.mpr ⟨hl_in, hm⟩
        rw [h_disjoint] at hm_inter; simp at hm_inter
      have h_freq_r : freqOf z r = 0 := freqOf_eq_zero_of_not_mem z r hr_not
      have h_sum_l : freqOf z l = fa + fb := by
        simp [freqOf] at h_sum; rw [h_freq_r] at h_sum; omega
      have h_split_r : splitLeaf r z a b fa fb = r :=
        splitLeaf_eq_of_z_not_mem r z a b fa fb hr_not
      have h_ih := ihl hcl hl_in h_sum_l
      have h_root_l : rootFreq (splitLeaf l z a b fa fb) = rootFreq l :=
        rootFreq_splitLeaf_eq l z a b fa fb hcl hl_in h_sum_l
      simp [splitLeaf, cost, h_split_r, h_ih, h_root_l]; omega
    · have hl_not : z ∉ alphabet l := by
        intro hm
        have hm_inter := Finset.mem_inter.mpr ⟨hm, hr_in⟩
        rw [h_disjoint] at hm_inter; simp at hm_inter
      have h_freq_l : freqOf z l = 0 := freqOf_eq_zero_of_not_mem z l hl_not
      have h_sum_r : freqOf z r = fa + fb := by
        simp [freqOf] at h_sum; rw [h_freq_l] at h_sum; omega
      have h_split_l : splitLeaf l z a b fa fb = l :=
        splitLeaf_eq_of_z_not_mem l z a b fa fb hl_not
      have h_ih := ihr hcr hr_in h_sum_r
      have h_root_r : rootFreq (splitLeaf r z a b fa fb) = rootFreq r :=
        rootFreq_splitLeaf_eq r z a b fa fb hcr hr_in h_sum_r
      simp [splitLeaf, cost, h_split_l, h_ih, h_root_r]; omega


lemma z_not_mem_alphabet_splitLeaf (t : HuffTree) (z a b fa fb : ℕ)
    (hz_ne_a : z ≠ a) (hz_ne_b : z ≠ b) :
    z ∉ alphabet (splitLeaf t z a b fa fb) := by
  induction t with
  | htLeaf sym f =>
    by_cases hz : sym = z
    · subst hz; simp [splitLeaf, alphabet, hz_ne_a, hz_ne_b]
    · simp [splitLeaf, alphabet, hz, Ne.symm hz]
  | htInner l r ihl ihr =>
    simp [splitLeaf, alphabet, ihl, ihr]

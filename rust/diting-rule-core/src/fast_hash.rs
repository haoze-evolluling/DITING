//! rustc's `FxHasher` construction, seeded per process: a multiply-rotate hash that is several
//! times faster than the default SipHash for the short strings the rule index is keyed by.
//!
//! Rule lists come from remote subscriptions, so the seed is drawn from `RandomState` instead of
//! being a constant: an attacker cannot precompute colliding keys offline to turn an import into an
//! O(n²) walk.

use std::hash::{BuildHasher, Hasher, RandomState};

const SEED: u64 = 0x51_7c_c1_b7_27_22_0a_95;

#[derive(Default)]
pub struct FxHasher {
    hash: u64,
}

impl FxHasher {
    #[inline]
    fn add(&mut self, word: u64) {
        self.hash = (self.hash.rotate_left(5) ^ word).wrapping_mul(SEED);
    }
}

impl Hasher for FxHasher {
    #[inline]
    fn write(&mut self, bytes: &[u8]) {
        let mut word = [0u8; 8];
        let mut filled = 0;
        for &byte in bytes {
            word[filled] = byte;
            filled += 1;
            if filled == 8 {
                self.add(u64::from_le_bytes(word));
                filled = 0;
            }
        }
        if filled > 0 {
            word[filled..].fill(0);
            self.add(u64::from_le_bytes(word));
        }
    }

    #[inline]
    fn write_u8(&mut self, value: u8) {
        self.add(u64::from(value));
    }

    #[inline]
    fn finish(&self) -> u64 {
        self.hash
    }
}

#[derive(Clone, Copy)]
pub struct FxBuildHasher {
    seed: u64,
}

impl Default for FxBuildHasher {
    fn default() -> Self {
        Self::new()
    }
}

impl FxBuildHasher {
    pub fn new() -> Self {
        let seed = RandomState::new().build_hasher().finish();
        Self { seed }
    }
}

impl BuildHasher for FxBuildHasher {
    type Hasher = FxHasher;

    fn build_hasher(&self) -> FxHasher {
        FxHasher { hash: self.seed }
    }
}

//! Access control facade.

mod control;

pub use control::{AccessControl, AccessStats};

#[cfg(test)]
mod tests;

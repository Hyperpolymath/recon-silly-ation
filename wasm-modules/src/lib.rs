use sha2::{Sha256, Digest};
use wasm_bindgen::prelude::*;

/// WASM-accelerated SHA-256 content hashing
/// Provides AOT-compiled performance for critical operations
#[wasm_bindgen]
pub fn hash_content(content: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(content.as_bytes());
    let result = hasher.finalize();

    // Convert to hex string
    result.iter()
        .map(|byte| format!("{:02x}", byte))
        .collect()
}

/// WASM-accelerated content normalization
/// Handles whitespace normalization faster than JS
#[wasm_bindgen]
pub fn normalize_content(content: &str) -> String {
    content
        .trim()
        .replace("\r\n", "\n")
        .lines()
        .map(|line| line.trim_end())
        .collect::<Vec<_>>()
        .join("\n")
        .split("\n\n\n")
        .collect::<Vec<_>>()
        .join("\n\n")
}

/// Batch hash multiple documents
/// Optimized for bulk operations
#[wasm_bindgen]
pub fn batch_hash(documents: &JsValue) -> Result<JsValue, JsValue> {
    // Parse JSON array of documents
    let docs: Vec<String> = serde_wasm_bindgen::from_value(documents.clone())?;

    let hashes: Vec<String> = docs
        .iter()
        .map(|doc| hash_content(doc))
        .collect();

    serde_wasm_bindgen::to_value(&hashes)
        .map_err(|e| JsValue::from_str(&e.to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_hash_content() {
        let content = "Hello, World!";
        let hash = hash_content(content);
        assert_eq!(hash.len(), 64); // SHA-256 = 64 hex chars
    }

    #[test]
    fn test_normalize_content() {
        let content = "  Hello  \r\n\r\n\r\nWorld  ";
        let normalized = normalize_content(content);
        assert_eq!(normalized, "Hello\n\nWorld");
    }
}

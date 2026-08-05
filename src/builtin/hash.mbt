///|
let blake3_iv : ReadOnlyArray[UInt] = [
  0x6A09E667U, 0xBB67AE85U, 0x3C6EF372U, 0xA54FF53AU, 0x510E527FU, 0x9B05688CU, 0x1F83D9ABU,
  0x5BE0CD19U,
]

///|
let blake3_permutation : ReadOnlyArray[Int] = [
  2, 6, 3, 10, 7, 0, 4, 13, 1, 11, 12, 5, 9, 14, 15, 8,
]

///|
const CHUNK_START : UInt = 1U

///|
const CHUNK_END : UInt = 2U

///|
const PARENT : UInt = 4U

///|
const ROOT : UInt = 8U

///|
priv struct Blake3Output {
  input_cv : Array[UInt]
  block : Array[UInt]
  counter : UInt64
  block_len : UInt
  flags : UInt
}

///|
fn rotate_right(value : UInt, amount : Int) -> UInt {
  (value >> amount) | (value << (32 - amount))
}

///|
fn mix(
  state : Array[UInt],
  a : Int,
  b : Int,
  c : Int,
  d : Int,
  x : UInt,
  y : UInt,
) -> Unit {
  state[a] = state[a] + state[b] + x
  state[d] = rotate_right(state[d] ^ state[a], 16)
  state[c] = state[c] + state[d]
  state[b] = rotate_right(state[b] ^ state[c], 12)
  state[a] = state[a] + state[b] + y
  state[d] = rotate_right(state[d] ^ state[a], 8)
  state[c] = state[c] + state[d]
  state[b] = rotate_right(state[b] ^ state[c], 7)
}

///|
fn round(state : Array[UInt], message : Array[UInt]) -> Unit {
  mix(state, 0, 4, 8, 12, message[0], message[1])
  mix(state, 1, 5, 9, 13, message[2], message[3])
  mix(state, 2, 6, 10, 14, message[4], message[5])
  mix(state, 3, 7, 11, 15, message[6], message[7])
  mix(state, 0, 5, 10, 15, message[8], message[9])
  mix(state, 1, 6, 11, 12, message[10], message[11])
  mix(state, 2, 7, 8, 13, message[12], message[13])
  mix(state, 3, 4, 9, 14, message[14], message[15])
}

///|
fn compress(
  input_cv : Array[UInt],
  block : Array[UInt],
  counter : UInt64,
  block_len : UInt,
  flags : UInt,
) -> Array[UInt] {
  let state = input_cv.copy()
  for word in blake3_iv[:4] {
    state.push(word)
  }
  state.push(counter.to_uint())
  state.push((counter >> 32).to_uint())
  state.push(block_len)
  state.push(flags)
  let mut message = block.copy()
  for _ in 0..<7 {
    round(state, message)
    let permuted : Array[UInt] = []
    for index in 0..<16 {
      permuted.push(message[blake3_permutation[index]])
    }
    message = permuted
  }
  let result : Array[UInt] = []
  for index in 0..<8 {
    result.push(state[index] ^ state[index + 8])
  }
  for index in 0..<8 {
    result.push(state[index + 8] ^ input_cv[index])
  }
  result
}

///|
fn copy_words(words : ArrayView[UInt]) -> Array[UInt] {
  let result : Array[UInt] = []
  for word in words {
    result.push(word)
  }
  result
}

///|
fn block_words(bytes : Bytes, start : Int, length : Int) -> Array[UInt] {
  let words : Array[UInt] = []
  for word_index in 0..<16 {
    let offset = start + word_index * 4
    let mut word = 0U
    for byte_index in 0..<4 {
      let index = offset + byte_index
      if index < start + length && index < bytes.length() {
        word = word | (bytes[index].to_uint() << (byte_index * 8))
      }
    }
    words.push(word)
  }
  words
}

///|
fn chunk_output(
  bytes : Bytes,
  start : Int,
  length : Int,
  counter : UInt64,
) -> Blake3Output {
  let block_count = if length == 0 { 1 } else { (length + 63) / 64 }
  let mut input_cv = copy_words(blake3_iv[:])
  for block_index in 0..<block_count {
    let block_start = start + block_index * 64
    let block_length = if block_index == block_count - 1 {
      length - block_index * 64
    } else {
      64
    }
    let mut flags = 0U
    if block_index == 0 {
      flags = flags | CHUNK_START
    }
    if block_index == block_count - 1 {
      flags = flags | CHUNK_END
    }
    let block = block_words(bytes, block_start, block_length)
    if block_index == block_count - 1 {
      return {
        input_cv,
        block,
        counter,
        block_len: block_length.reinterpret_as_uint(),
        flags,
      }
    }
    let compressed = compress(input_cv, block, counter, 64U, flags)
    input_cv = copy_words(compressed[:8])
  }
  abort("unreachable")
}

///|
fn output_chaining_value(output : Blake3Output) -> Array[UInt] {
  let compressed = compress(
    output.input_cv,
    output.block,
    output.counter,
    output.block_len,
    output.flags,
  )
  copy_words(compressed[:8])
}

///|
fn parent_output(left : Array[UInt], right : Array[UInt]) -> Blake3Output {
  let block = left.copy()
  for word in right {
    block.push(word)
  }
  {
    input_cv: copy_words(blake3_iv[:]),
    block,
    counter: 0UL,
    block_len: 64U,
    flags: PARENT,
  }
}

///|
fn subtree(
  bytes : Bytes,
  start : Int,
  length : Int,
  counter : UInt64,
) -> Blake3Output {
  if length <= 1024 {
    return chunk_output(bytes, start, length, counter)
  }
  let chunks = (length + 1023) / 1024
  let mut left_chunks = 1
  while left_chunks * 2 < chunks {
    left_chunks = left_chunks * 2
  }
  let left_length = left_chunks * 1024
  let left = subtree(bytes, start, left_length, counter)
  let right = subtree(
    bytes,
    start + left_length,
    length - left_length,
    counter + left_chunks.to_uint64(),
  )
  parent_output(output_chaining_value(left), output_chaining_value(right))
}

///|
fn hex_word(value : UInt, builder : StringBuilder) -> Unit {
  for index in 0..<4 {
    let byte = (value >> (index * 8)).to_byte()
    let digits = [
      '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e',
      'f',
    ]
    builder.write_char(digits[(byte.to_int() >> 4) & 15])
    builder.write_char(digits[byte.to_int() & 15])
  }
}

///|
pub fn blake3_bytes(bytes : Bytes) -> String {
  let output = subtree(bytes, 0, bytes.length(), 0UL)
  let words = compress(
    output.input_cv,
    output.block,
    output.counter,
    output.block_len,
    output.flags | ROOT,
  )
  let builder = StringBuilder()
  for index in 0..<8 {
    hex_word(words[index], builder)
  }
  builder.to_string()
}

///|
/// Hash a sequence of chunks using the same canonical byte concatenation as
/// the one-shot API. The chunk boundary is intentionally not part of the
/// digest, which makes adapters and in-memory test hosts interchangeable.
pub fn blake3_chunks(chunks : ArrayView[Bytes]) -> String {
  let bytes : Array[Byte] = []
  for chunk in chunks {
    for byte in chunk {
      bytes.push(byte)
    }
  }
  blake3_bytes(Bytes::from_array(bytes))
}

///|
pub fn sha256_bytes(bytes : Bytes) -> String {
  let digest = @crypto.sha256(bytes)
  let builder = StringBuilder()
  for byte in digest {
    builder.write_string(byte.to_hex())
  }
  builder.to_string()
}

///|
pub fn sha256_chunks(chunks : ArrayView[Bytes]) -> String {
  let bytes : Array[Byte] = []
  for chunk in chunks {
    for byte in chunk {
      bytes.push(byte)
    }
  }
  sha256_bytes(Bytes::from_array(bytes))
}

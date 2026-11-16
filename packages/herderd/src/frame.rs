//! Length-prefixed frames over any byte stream.
//!
//! A frame is a big-endian `u32` byte count and then that many bytes. Nothing
//! here knows what the bytes mean, or what carries them: a Unix socket, a
//! child's stdio over SSH and an in-memory buffer are all the same to it.

use std::io::{self, Read, Write};

/// The largest payload a frame may carry. A peer announcing more is broken or
/// hostile, and is refused before anything is allocated for it.
pub const MAX_FRAME: u32 = 16 * 1024 * 1024;

pub fn write_frame<W: Write>(out: &mut W, payload: &[u8]) -> io::Result<()> {
    let len = u32::try_from(payload.len())
        .ok()
        .filter(|len| *len <= MAX_FRAME)
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "frame too large"))?;
    out.write_all(&len.to_be_bytes())?;
    out.write_all(payload)?;
    out.flush()
}

/// The next frame's payload, or `None` if the stream ended cleanly between
/// frames. Ending in the middle of one is an error.
pub fn read_frame<R: Read>(input: &mut R) -> io::Result<Option<Vec<u8>>> {
    let mut header = [0u8; 4];
    let mut filled = 0;
    while filled < header.len() {
        match input.read(&mut header[filled..])? {
            0 if filled == 0 => return Ok(None),
            0 => return Err(io::ErrorKind::UnexpectedEof.into()),
            n => filled += n,
        }
    }
    let len = u32::from_be_bytes(header);
    if len > MAX_FRAME {
        return Err(io::Error::new(io::ErrorKind::InvalidData, "frame too large"));
    }
    let mut payload = vec![0u8; len as usize];
    input.read_exact(&mut payload)?;
    Ok(Some(payload))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;

    #[test]
    fn round_trips_frames_in_order() {
        let mut wire = Vec::new();
        write_frame(&mut wire, b"one").unwrap();
        write_frame(&mut wire, b"").unwrap();
        write_frame(&mut wire, b"three").unwrap();

        let mut input = Cursor::new(wire);
        assert_eq!(read_frame(&mut input).unwrap().unwrap(), b"one");
        assert_eq!(read_frame(&mut input).unwrap().unwrap(), b"");
        assert_eq!(read_frame(&mut input).unwrap().unwrap(), b"three");
        assert!(read_frame(&mut input).unwrap().is_none());
    }

    #[test]
    fn a_stream_cut_mid_frame_is_an_error() {
        let mut input = Cursor::new(vec![0, 0, 0, 5, b'a', b'b']);
        assert!(read_frame(&mut input).is_err());
        let mut input = Cursor::new(vec![0, 0]);
        assert!(read_frame(&mut input).is_err());
    }

    #[test]
    fn refuses_an_oversized_frame_before_allocating() {
        let mut input = Cursor::new((MAX_FRAME + 1).to_be_bytes().to_vec());
        let error = read_frame(&mut input).unwrap_err();
        assert_eq!(error.kind(), io::ErrorKind::InvalidData);
    }
}

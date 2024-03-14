# MatFile

> This repository hosts an implementation of a customized matrix file format.

The provided information describes a custom matrix file format, including details about the header and data sections.

Here's a breakdown:

## Format:

- **File Extension:** `.mat`
- **Header:**
  - Size: 7 bytes
  - Content:
    - Data Type (2 bytes): Identifies the data type stored in the matrix (unsigned/signed integers, floating-point).
    - Number of Rows (2 bytes): Unsigned 16-bit integer representing the number of rows (maximum 65535).
    - Number of Columns (2 bytes): Unsigned 16-bit integer representing the number of columns (maximum 65535).
    - Newline character (1 byte): Always `\n` (0x0a) to mark the end of the header.
- **Data:**
  - Encoding: Row-major order (elements filled row-wise).
  - Delimiter: No delimiters or line breaks within the data chunk.

## Key Points:

- This format stores basic information about the data type, dimensions, and the data itself.
- The limited size for rows and columns (65535) restricts the maximum matrix size.
- The absence of delimiters within the data section requires knowing the data type beforehand for proper interpretation.

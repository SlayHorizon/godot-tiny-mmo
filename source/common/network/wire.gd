class_name Wire


enum Type {
	VARIANT,
	BOOL,
	U8, U16, U32, U64,
	S8, S16, S32, S64,
	F16, F32, F64,
	STR_UTF8_U16, STR_UTF8_U32,
	STR_ASCII_U16, STR_ASCII_U32,
	BYTES_U16, BYTES_U32,
	VEC2_F32
}

# U / Unsigned byte
# S / Signed byte
# put_double / f64 / 64 bits
# put_float / f32 / 32 bits / float, single precision
# put_half / f16 / 16 bits/ half, half precision

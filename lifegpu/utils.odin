package lifevk

import "core:strings"

bytes_to_string :: proc(arr: ^[$N]byte) -> string {
	return strings.truncate_to_byte(string(arr[:]), 0)
}

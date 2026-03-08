function readfile(path,    content, line, cmd) {
	content = ""
	cmd = "cat " path
	while ((cmd | getline line) > 0) {
		if (content != "") content = content "\n"
		content = content line
	}
	close(cmd)
	return content
}

{ content = content $0 "\n" }

END {
	result = ""; remaining = content
	while (match(remaining, /\$\{[A-Z_][A-Z0-9_]*\}/)) {
		varname = substr(remaining, RSTART+2, RLENGTH-3)
		val = ENVIRON[varname]
		if (val == "" && ENVIRON[varname "_FILE"] != "") {
			val = readfile(ENVIRON[varname "_FILE"])
		}
		result = result substr(remaining, 1, RSTART-1) val
		remaining = substr(remaining, RSTART+RLENGTH)
	}
	printf "%s%s", result, remaining
}

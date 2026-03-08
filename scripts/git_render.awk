{ content = content $0 "\n" }
END {
	result = ""; remaining = content
	while (match(remaining, /\$\{[A-Z_][A-Z0-9_]*\}/)) {
		varname = substr(remaining, RSTART+2, RLENGTH-3)
		result = result substr(remaining, 1, RSTART-1) ENVIRON[varname]
		remaining = substr(remaining, RSTART+RLENGTH)
	}
	printf "%s%s", result, remaining
}

#!/bin/sh
# gen-sitemap.sh - generate sitemap.xml from built site
set -eu

dir="${1:-site}"
url="${2:-https://www.dr-dos.org}"
out="${dir}/sitemap.xml"

[ -d "$dir" ] || { printf 'error: %s not found\n' "$dir" >&2; exit 1; }

lastmod() {
	org="src/${1%.html}.org"
	ts=$(git log -1 --format='%cI' -- "$org" 2>/dev/null || true)
	printf '%s' "${ts:-$(date -u +%Y-%m-%dT%H:%M:%S+00:00)}"
}

priority() {
	case "$1" in
	index.html) printf '1.00' ;;
	*/blog.html) printf '0.90' ;;
	aboutme.html|pgp.html) printf '0.80' ;;
	blog/posts/*.html) printf '0.60' ;;
	*) printf '0.50' ;;
	esac
}

cat > "$out" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
EOF

find "$dir" -name '*.html' -type f | sort | while read -r f; do
	rel="${f#"$dir"/}"
	case "$rel" in txt/*|*rss*) continue ;; esac

	case "$rel" in
	index.html) loc="${url}/" ;;
	*) loc="${url}/${rel}" ;;
	esac

	cat >> "$out" <<EOF
  <url>
    <loc>${loc}</loc>
    <lastmod>$(lastmod "$rel")</lastmod>
    <priority>$(priority "$rel")</priority>
  </url>
EOF
done

printf '</urlset>\n' >> "$out"
printf 'sitemap: %s (%d urls)\n' "$out" "$(grep -c '<url>' "$out")"

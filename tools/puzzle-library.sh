#!/bin/sh
# puzzle-library.sh DATABASE > chess/puzzles.csv
#
# Cuts the puzzles x-chess ships from the lichess puzzle database
# (https://database.lichess.org/#puzzles, CC0), DATABASE its .csv or
# .csv.zst.  Each puzzle is filed under the first of these themes it has:
#
#   mateIn5 mateIn4 mateIn3 mateIn2 mateIn1 fork pin skewer
#   discoveredAttack trappedPiece hangingPiece endgame
#
# and under one of five rating bands, below 1000, 1000-1399, 1400-1799,
# 1800-2199 and 2200 up.  Of each theme and band, the PER most played
# (40 unless PER is set) of those well liked (Popularity 90 or more),
# played often (NbPlays 1000 or more) and rated surely (RatingDeviation
# 90 or less) are kept.  They are written in the database's form, header
# first, easiest first, with no game link or opening tags.

PER=${PER:-40}
db=$1
if [ -z "$db" ] || [ ! -r "$db" ]; then
	echo "usage: puzzle-library.sh DATABASE > chess/puzzles.csv" >&2
	exit 2
fi
case $db in
	*.zst) read_db() { zstd -dc "$db"; } ;;
	*) read_db() { cat "$db"; } ;;
esac

tab=$(printf '\t')

echo "PuzzleId,FEN,Moves,Rating,RatingDeviation,Popularity,NbPlays,Themes,GameUrl,OpeningTags"
read_db | awk -F, '
	BEGIN {
		n = split("mateIn5 mateIn4 mateIn3 mateIn2 mateIn1 fork pin skewer discoveredAttack trappedPiece hangingPiece endgame", order, " ")
	}
	NR == 1 { next }
	$6 < 90 || $7 < 1000 || $5 > 90 { next }
	{
		split($8, ts, " ")
		for (t in has) delete has[t]
		for (i in ts) has[ts[i]] = 1
		theme = 0
		for (i = 1; i <= n; i++) if (order[i] in has) { theme = i; break }
		if (theme == 0) next
		r = $4 + 0
		band = r < 1000 ? 1 : r < 1400 ? 2 : r < 1800 ? 3 : r < 2200 ? 4 : 5
		# theme, band, plays, rating, then the row: tabs, since a FEN has spaces
		printf "%d\t%d\t%d\t%d\t%s,%s,%s,%s,%s,%s,%s,%s,,\n", theme, band, $7, r, $1, $2, $3, $4, $5, $6, $7, $8
	}' |
	sort -t "$tab" -k1,1n -k2,2n -k3,3nr |
	awk -F '\t' -v per="$PER" '++taken[$1 " " $2] <= per { print $4 "\t" $5 }' |
	sort -t "$tab" -k1,1n -s |
	cut -f 2-

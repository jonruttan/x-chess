#!/bin/sh
# x-chess -- a chess engine on x-lang
#
# tests/fake-engine.sh -- a UCI engine for the specs to start
#
# @author [Jon Ruttan](jonruttan@gmail.com)
# @copyright 2026 Jon Ruttan
# @license MIT No Attribution (MIT-0)
#
#   sh tests/fake-engine.sh [MOVE]
#
# It answers uci and isready, and every go with two info lines and
# bestmove MOVE (e7e5 when not given): the specs play it from positions
# where MOVE is legal.  MOVE none answers bestmove (none).
move="${1:-e7e5}"
while read -r line; do
	case "$line" in
	uci) printf 'id name Fake 1.0\nid author nobody\nuciok\n' ;;
	isready) printf 'readyok\n' ;;
	go*)
		if [ "$move" = none ]; then
			printf 'info depth 1 score mate 0\nbestmove (none)\n'
		else
			printf 'info depth 1 score cp 13 nodes 20 time 3 pv %s\n' "$move"
			printf 'info depth 2 score cp -21 nodes 40 time 5 pv %s g1f3\n' "$move"
			printf 'bestmove %s\n' "$move"
		fi
		;;
	quit) exit 0 ;;
	esac
done

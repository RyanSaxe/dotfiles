package popup

import (
	"cmp"
	"slices"
	"strings"

	"github.com/charmbracelet/bubbles/list"
	"github.com/junegunn/fzf/src/algo"
	"github.com/junegunn/fzf/src/util"
)

func init() { algo.Init("default") }

// A Rank is a target that matched: its index and the runes that matched.
type Rank struct {
	Index     int
	Positions []int
}

// Match ranks targets with fzf's own matching and its default order: best
// score first, then the shorter target, then the order they came in. As in
// fzf, a capital letter makes the match case-sensitive.
func Match(term string, targets []string) []Rank {
	caseSensitive := term != strings.ToLower(term)
	pattern, slab := []rune(term), util.MakeSlab(100*1024, 2048)
	type scored struct {
		rank         Rank
		score, chars int
	}
	var found []scored
	for i, t := range targets {
		text := util.ToChars([]byte(t))
		res, pos := algo.FuzzyMatchV2(caseSensitive, true, true, &text, pattern, true, slab)
		if res.Start >= 0 && pos != nil {
			found = append(found, scored{Rank{i, slices.Clone(*pos)}, res.Score, text.Length()})
		}
	}
	slices.SortStableFunc(found, func(a, b scored) int { return cmp.Or(b.score-a.score, a.chars-b.chars) })
	ranks := make([]Rank, len(found))
	for i, f := range found {
		ranks[i] = f.rank
	}
	return ranks
}

// listFilter is Match in the form the list asks for.
func listFilter(term string, targets []string) []list.Rank {
	ranks := Match(term, targets)
	out := make([]list.Rank, len(ranks))
	for i, r := range ranks {
		out[i] = list.Rank{Index: r.Index, MatchedIndexes: r.Positions}
	}
	return out
}

import Foundation
import NotchyCore

func runLineSplitterChecks() {
    var s = LineSplitter()
    check("splitter: whole lines", s.feed(Data("a\nb\n".utf8)).map(String.init) == ["a", "b"])
    check("splitter: partial carried", s.feed(Data("ab".utf8)).isEmpty)
    check("splitter: partial completed", s.feed(Data("c\nd".utf8)).map(String.init) == ["abc"])
    check("splitter: tail kept", s.feed(Data("e\n".utf8)).map(String.init) == ["de"])
    var big = LineSplitter(maxBuffer: 8)
    check("splitter: oversize dropped", big.feed(Data("123456789".utf8)).isEmpty)
    check("splitter: skips to newline, resumes", big.feed(Data("xx\nok\n".utf8)).map(String.init) == ["ok"])
    var big2 = LineSplitter(maxBuffer: 8)
    check("splitter: oversize in one chunk", big2.feed(Data("123456789\nok\n".utf8)).map(String.init) == ["ok"])
}

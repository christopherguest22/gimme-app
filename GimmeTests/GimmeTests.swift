import XCTest
@testable import Gimme

final class GeoTests: XCTestCase {
    func testOffsetRoundTripsDistanceAndBearing() {
        let start = Coordinate(33.0, -117.0)
        let end = Geo.offset(start, meters: 300, bearing: 45)
        XCTAssertEqual(Geo.meters(start, end), 300, accuracy: 1)
        XCTAssertEqual(Geo.bearing(from: start, to: end), 45, accuracy: 0.5)
    }

    func testYards() {
        let start = Coordinate(33.0, -117.0)
        XCTAssertEqual(Geo.yards(start, Geo.offset(start, meters: 91.44, bearing: 0)), 100)
    }

    func testDemoCourseHas18HolesAndPar72() {
        let course = DemoCourse.make(firstTee: Coordinate(33.0, -117.0))
        XCTAssertEqual(course.holes.count, 18)
        XCTAssertEqual(course.par, 72)
    }
}

final class ScoringTests: XCTestCase {
    private let course = DemoCourse.make(firstTee: Coordinate(33.0, -117.0))
    private let me = Player(id: "me", name: "Me", avatar: "🏌️")

    private func round(strokesOverPar: Int) -> Round {
        var round = Round(course: course, players: [me])
        for hole in course.holes {
            round.setStrokes(hole.par + (hole.number <= strokesOverPar ? 1 : 0), for: me.id, hole: hole.number)
        }
        return round
    }

    func testTotalsAndToPar() {
        let r = round(strokesOverPar: 5)
        XCTAssertEqual(r.total(me.id), 77)
        XCTAssertEqual(r.toPar(me.id), 5)
        XCTAssertEqual(Scoring.formatToPar(5), "+5")
        XCTAssertEqual(Scoring.formatToPar(0), "E")
    }

    func testHandicapNeedsThreeRounds() {
        XCTAssertNil(Scoring.handicapEstimate(rounds: [round(strokesOverPar: 5)], playerId: me.id))
        let rounds = [round(strokesOverPar: 5), round(strokesOverPar: 10), round(strokesOverPar: 8)]
        XCTAssertEqual(Scoring.handicapEstimate(rounds: rounds, playerId: me.id), 5.0)
    }

    func testChallenges() {
        XCTAssertTrue(Drop.Challenge.parOrBetter.isMet(strokes: 4, par: 4))
        XCTAssertFalse(Drop.Challenge.birdieOrBetter.isMet(strokes: 4, par: 4))
    }
}

final class DropTests: XCTestCase {
    func testClaimRequiresAVisitOnTheHole() async throws {
        let backend = MockBackend()
        let course = DemoCourse.make(firstTee: Coordinate(33.0, -117.0))
        let round = Round(course: course, players: [Player(id: "me", name: "Me", avatar: "🏌️")])
        let drop = try await backend.drops(for: course).first { $0.challenge == .none }!

        do {
            try await backend.visit(drop: drop, round: round, at: course.holes[0].tee)
            XCTFail("A visit from the wrong place should fail")
        } catch {}
        do {
            _ = try await backend.claim(drop: drop, round: round)
            XCTFail("Claim without a visit should fail")
        } catch {}

        try await backend.visit(drop: drop, round: round, at: drop.center)
        let prize = try await backend.claim(drop: drop, round: round)
        XCTAssertEqual(prize.drop.remaining, drop.remaining - 1)

        do {
            _ = try await backend.claim(drop: drop, round: round)
            XCTFail("Second claim should fail")
        } catch {}
    }

    func testChallengeDropNeedsTheScore() async throws {
        let backend = MockBackend()
        let course = DemoCourse.make(firstTee: Coordinate(33.0, -117.0))
        var round = Round(course: course, players: [Player(id: "me", name: "Me", avatar: "🏌️")])
        let drop = try await backend.drops(for: course).first { $0.challenge == .parOrBetter }!
        try await backend.visit(drop: drop, round: round, at: drop.center)

        round.setStrokes(round.pars[drop.holeNumber - 1] + 1, for: "me", hole: drop.holeNumber)
        do {
            _ = try await backend.claim(drop: drop, round: round)
            XCTFail("Bogey should not win a par-or-better drop")
        } catch {}

        round.setStrokes(round.pars[drop.holeNumber - 1], for: "me", hole: drop.holeNumber)
        _ = try await backend.claim(drop: drop, round: round)
    }
}

final class SideGameTests: XCTestCase {
    private let course = DemoCourse.make(firstTee: Coordinate(33.0, -117.0))
    private let a = Player(id: "a", name: "A", avatar: "🅰️")
    private let b = Player(id: "b", name: "B", avatar: "🅱️")

    func testSkinsCarryOverOnTies() {
        var round = Round(course: course, players: [a, b])
        // Hole 1 tied, hole 2 won by A (worth 2), hole 3 won by B.
        for (hole, scores) in [(1, (4, 4)), (2, (3, 4)), (3, (4, 3))] {
            round.setStrokes(scores.0, for: "a", hole: hole)
            round.setStrokes(scores.1, for: "b", hole: hole)
        }
        let result = Scoring.skins(round)
        XCTAssertEqual(result.skins["a"], 2)
        XCTAssertEqual(result.skins["b"], 1)
        XCTAssertEqual(result.carryover, 0)
    }

    func testNassauLeader() {
        var round = Round(course: course, players: [a, b])
        for hole in 1...9 {
            round.setStrokes(4, for: "a", hole: hole)
            round.setStrokes(5, for: "b", hole: hole)
        }
        let legs = Scoring.nassau(round)
        XCTAssertEqual(legs.first { $0.name == "Front 9" }?.leader, "a")
        XCTAssertEqual(legs.first { $0.name == "Front 9" }?.margin, 9)
        XCTAssertEqual(legs.first { $0.name == "Back 9" }?.holesCounted, 0)
    }
}

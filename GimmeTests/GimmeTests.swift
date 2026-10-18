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
    func testClaimRequiresBeingOnTheHole() async throws {
        let backend = MockBackend()
        let course = DemoCourse.make(firstTee: Coordinate(33.0, -117.0))
        let round = Round(course: course, players: [Player(id: "me", name: "Me", avatar: "🏌️")])
        let drop = try await backend.drops(for: course).first { $0.challenge == .none }!

        do {
            _ = try await backend.claim(drop: drop, round: round, at: course.holes[0].tee, holeStrokes: nil)
            XCTFail("Claim from the wrong place should fail")
        } catch {}

        let prize = try await backend.claim(drop: drop, round: round, at: drop.center, holeStrokes: nil)
        XCTAssertEqual(prize.drop.remaining, drop.remaining - 1)

        do {
            _ = try await backend.claim(drop: drop, round: round, at: drop.center, holeStrokes: nil)
            XCTFail("Second claim should fail")
        } catch {}
    }
}

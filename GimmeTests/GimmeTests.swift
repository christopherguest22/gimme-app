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

final class PlaysLikeTests: XCTestCase {
    func testHeadwindAddsTenPercentAtTenMph() {
        // Shot heading north into a wind blowing from the north.
        let calm = Conditions(windMph: 10, windFromDegrees: 0, temperatureF: 75)
        XCTAssertEqual(PlaysLike.yards(100, shotBearing: 0, conditions: calm).yards, 110)
    }

    func testTailwindTakesOffFivePercentAtTenMph() {
        let wind = Conditions(windMph: 10, windFromDegrees: 180, temperatureF: 75)
        XCTAssertEqual(PlaysLike.yards(100, shotBearing: 0, conditions: wind).yards, 95)
    }

    func testUphillPlaysLonger() {
        // 9.144 m uphill is 10 yards.
        XCTAssertEqual(PlaysLike.yards(150, shotBearing: 0, rise: 9.144).yards, 160)
        XCTAssertEqual(PlaysLike.yards(150, shotBearing: 0, rise: -9.144).yards, 140)
    }

    func testColdPlaysLonger() {
        let cold = Conditions(windMph: 0, windFromDegrees: 0, temperatureF: 55)
        XCTAssertEqual(PlaysLike.yards(150, shotBearing: 0, conditions: cold).yards, 154)
    }

    func testClubSuggestion() {
        XCTAssertEqual(Bag.standard.club(for: 162)?.shortName, "6i")
        XCTAssertEqual(Bag.standard.club(for: 300)?.shortName, "Dr")
        XCTAssertNil(Bag.standard.club(for: 20))
    }
}

final class ScorecardTests: XCTestCase {
    private let detail = """
    {"course_name":"Sample Links",
     "tees":[{"tee_key":"blue-male","tee_name":"Blue","tee_color":"blue","gender":"Male","course_rating":71.2,"slope":128,"par":72,"yardage":6600},
             {"tee_key":"white-male","tee_name":"White","tee_color":"white","gender":"Male","course_rating":69.5,"slope":122,"par":72,"yardage":6200}],
     "holes_data":[{"number":1,"par":4,"handicap_index":5,"yardages":{"web":411,"blue":411,"white":388},
                    "tee_coords":null,"green":{"center":null,"front":null,"back":null},"hazards":[]},
                   {"number":2,"par":3,"handicap_index":17,"yardages":{"blue":172,"white":150},
                    "tee_coords":{"lat":40.001,"lng":-75.0},"green":{"center":{"lat":40.0025,"lng":-75.0},"front":null,"back":null}}]}
    """.data(using: .utf8)!

    func testParsesTeesAndHoles() throws {
        let card = try XCTUnwrap(ScorecardService.parse(detail))
        XCTAssertEqual(card.tees.map(\.name), ["Blue", "White"])
        XCTAssertEqual(card.tees.first?.slope, 128)
        XCTAssertEqual(card.holes[0].handicap, 5)
        XCTAssertEqual(card.holes[0].yardages, ["Blue": 411, "White": 388])
        XCTAssertEqual(card.holes[1].tee, Coordinate(40.001, -75.0))
    }

    func testMergeAddsScorecardToMappedHoles() throws {
        let card = try XCTUnwrap(ScorecardService.parse(detail))
        let mapped = DemoCourse.make(firstTee: Coordinate(40, -75))
        var course = mapped
        for i in course.holes.indices { course.holes[i].yardages = nil; course.holes[i].handicap = nil }
        let merged = ScorecardService.merge(card, into: course)
        XCTAssertEqual(merged.hole(1)?.yardage("blue"), 411)
        XCTAssertEqual(merged.hole(2)?.par, 3)
        XCTAssertEqual(merged.hole(2)?.handicap, 17)
        XCTAssertEqual(merged.teeNames, ["Blue", "White"])
    }

    func testBuildsHolesFromScorecardWhenMapIsEmpty() throws {
        let card = try XCTUnwrap(ScorecardService.parse(detail))
        let empty = Course(id: "way/1", name: "Sample Links", holes: [], source: "© OpenStreetMap contributors")
        let merged = ScorecardService.merge(card, into: empty)
        // Only hole 2 has tee and green positions.
        XCTAssertEqual(merged.holes.map(\.number), [2])
    }

    func testDemoCourseHasTees() {
        let course = DemoCourse.make(firstTee: Coordinate(40, -75))
        XCTAssertEqual(course.teeNames, ["Blue", "White", "Red"])
        XCTAssertEqual(Set(course.holes.compactMap(\.handicap)).count, 18)
    }
}

final class KiawahPackTests: XCTestCase {
    func testAllSevenCoursesWithOceanFirst() {
        let names = CoursePack.courses.map(\.name)
        XCTAssertEqual(names.count, 7)
        XCTAssertEqual(names.first, "The Ocean Course")
        XCTAssertEqual(Set(names), ["The Ocean Course", "Turtle Point", "Cougar Point", "Osprey Point",
                                    "Oak Point", "Cassique", "The River Course"])
    }

    func testOceanCourseHole18() throws {
        let ocean = try XCTUnwrap(CoursePack.featured)
        let eighteen = try XCTUnwrap(ocean.holes.first { $0.number == 18 })
        XCTAssertEqual(eighteen.par, 4)
        XCTAssertEqual(eighteen.handicap, 6)
        XCTAssertEqual(eighteen.yardages["Tournament"], 439)
    }

    func testTeeTotalsMatchHoleYardages() {
        for course in CoursePack.courses where !course.holes.isEmpty {
            XCTAssertTrue(course.scorecard.isConsistent, course.name)
            for tee in course.tees {
                let total = course.holes.compactMap { $0.yardages[tee.name] }.reduce(0, +)
                XCTAssertEqual(Double(total), Double(tee.yardage), accuracy: Double(tee.yardage) * 0.01, "\(course.name) \(tee.name)")
            }
        }
    }

    func testHalfFilledScorecardIsIgnored() {
        // Every hole listed as par 5 (as one public listing has for Oak Point) must not overwrite the map.
        let card = ScorecardService.Scorecard(
            name: "Oak Point",
            tees: [TeeSet(name: "Oak", par: 72, yardage: 6450)],
            holes: (1...18).map { .init(number: $0, par: 5, handicap: $0, yardages: [:]) })
        XCTAssertFalse(card.isConsistent)
        let demo = DemoCourse.make(firstTee: Coordinate(32.6, -80.1))
        XCTAssertEqual(ScorecardService.merge(card, into: demo).par, demo.par)
    }

    func testStandInLayoutUsesScorecard() throws {
        let ocean = try XCTUnwrap(CoursePack.featured)
        let course = DemoCourse.provisional(id: ocean.id, name: ocean.name, around: ocean.center, card: ocean.scorecard)
        XCTAssertEqual(course.holes.count, 18)
        XCTAssertEqual(course.needsMapping, true)
        XCTAssertEqual(course.hole(18)?.lengthYards ?? 0, 439, accuracy: 2)
    }
}

final class SettlementTests: XCTestCase {
    private func round(_ cards: [String: [Int?]]) -> Round {
        let course = DemoCourse.make(firstTee: Coordinate(32.6, -80.0))
        let players = cards.keys.sorted().map { Player(id: $0, name: $0.capitalized, avatar: "🏌️") }
        var round = Round(course: course, players: players)
        for (id, card) in cards {
            for (i, strokes) in card.enumerated() { round.setStrokes(strokes, for: id, hole: i + 1) }
        }
        return round
    }

    func testTwoSkinsAtTenDollarsMeansEachOtherPlayerOwesTwenty() {
        // Chris wins holes 1 and 2 outright; hole 3 is tied.
        let r = round(["chris": [3, 3, 4], "jake": [4, 4, 4], "dev": [5, 4, 4]])
        let balances = Settlement.balances(r, stakes: Stakes(perSkin: 10))
        XCTAssertEqual(balances["chris"], 40)
        XCTAssertEqual(balances["jake"], -20)
        XCTAssertEqual(balances["dev"], -20)
        let payments = Settlement.payments(balances)
        XCTAssertEqual(Set(payments), [Payment(from: "jake", to: "chris", amount: 20), Payment(from: "dev", to: "chris", amount: 20)])
    }

    func testPaymentsNetOutAcrossGames() {
        // Jake wins a skin, Chris wins two: Jake only pays Chris the difference.
        let r = round(["chris": [3, 3, 5], "jake": [4, 4, 4]])
        let payments = Settlement.payments(Settlement.balances(r, stakes: Stakes(perSkin: 5)))
        XCTAssertEqual(payments, [Payment(from: "jake", to: "chris", amount: 5)])
    }

    func testNassauOnlyPaysFinishedLegs() {
        let front = Array(repeating: Optional(4), count: 9)
        let r = round(["chris": front.map { $0.map { $0 - 1 } }, "jake": front])
        let stakes = Stakes(perNassauLeg: 10)
        // Front nine finished, Chris leads: Jake owes $10. Back nine and overall aren't finished.
        XCTAssertEqual(Settlement.balances(r, stakes: stakes)["jake"], -10)
    }

    func testBalancesAlwaysSumToZero() {
        let r = round(["a": [3, 5, 4, 4], "b": [4, 4, 4, 3], "c": [5, 4, 3, 4], "d": [4, 4, 5, 5]])
        let total = Settlement.balances(r, stakes: Stakes(perSkin: 7, perNassauLeg: 3)).values.reduce(0, +)
        XCTAssertEqual(total, 0, accuracy: 0.001)
    }

    func testPayLinks() {
        XCTAssertEqual(PayLinks.cashApp(cashtag: "$chrisg", amount: 20)?.absoluteString, "https://cash.app/$chrisg/20.00")
        let venmo = PayLinks.venmo(handle: "@chris-g", amount: 20, note: "Skins")?.absoluteString ?? ""
        XCTAssertTrue(venmo.hasPrefix("https://venmo.com/chris-g?txn=pay&amount=20.00"))
    }
}

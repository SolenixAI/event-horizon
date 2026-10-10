import CoreGraphics
import Testing
@testable import Glimmer

/// The first-launch stage's seams: a step and live facts in, the scene out,
/// and the time maps that move it. No view, no clock, no OS.
struct OnboardingSceneTests {

    private func scene(_ step: OnboardingStep, found: Int = 0, paired: Bool = false,
                       permissions: [OnboardingItem: OnboardingItemState] = [:]) -> OnboardingScene {
        OnboardingScene.make(step: step, facts: OnboardingSceneFacts(
            foundPCs: found, paired: paired, permissions: permissions))
    }

    // MARK: Camera and world

    /// The stage fills whatever window it is in; these tests use one window size.
    private let window = CGSize(width: 1180, height: 843)

    private func camera(_ step: OnboardingStep) -> StageCamera {
        StageCamera(pose: scene(step).pose, size: window)
    }

    @Test func theHoleSitsWhereTheCameraFramesIt() throws {
        for step in OnboardingStep.allCases where step != .ready {
            let camera = camera(step)
            let hole = try #require(camera.project(StageWorld.hole))
            #expect(abs(hole.point.x - camera.principal.x) < 0.001)
            #expect(abs(hole.point.y - camera.principal.y) < 0.001)
        }
    }

    @Test func welcomeFramesTheHoleAboveTheWordsAndSetupMovesItRight() throws {
        let welcome = try #require(camera(.welcome).project(StageWorld.hole)).point
        #expect(welcome.x > window.width / 2)
        #expect(welcome.y < window.height / 2)
        let find = try #require(camera(.findPC).project(StageWorld.hole)).point
        #expect(find.x > welcome.x)
    }

    @Test func theShadowScalesWithTheWindow() {
        let pose = scene(.welcome).pose
        let small = StageCamera(pose: pose, size: CGSize(width: 800, height: 500)).shadowRadius
        let large = StageCamera(pose: pose, size: CGSize(width: 1600, height: 1000)).shadowRadius
        #expect(abs(large - small * 2) < 0.0001)
    }

    @Test func theMacAndThePCStayOnTheStageAndClearOfTheWordsDuringSetup() throws {
        for step in [OnboardingStep.findPC, .pair, .controls] {
            let camera = camera(step)
            for place in [StageWorld.mac, StageWorld.pcAnchors[0]] {
                let seen = try #require(camera.project(place)).point
                #expect(seen.x > 0 && seen.x < window.width)
                #expect(seen.y > 0 && seen.y < window.height)
                // The words and panels live in the lower left, 64 to 564 points in.
                #expect(!(seen.x < 600 && seen.y > 300))
                #expect(!camera.isHidden(place))
            }
        }
    }

    @Test func aPointBehindTheShadowIsHidden() {
        let camera = camera(.welcome)
        #expect(camera.isHidden(-camera.position * 0.5))
        #expect(!camera.isHidden(camera.position * 0.5))
    }

    @Test func setupOrbitsUpAndAroundAndPullsBackThenReadyDivesInsideTheHorizon() {
        let setup: [OnboardingStep] = [.welcome, .findPC, .pair, .controls]
        let poses = setup.map { scene($0).pose }
        #expect(zip(poses, poses.dropFirst()).allSatisfy { $0.distance < $1.distance })
        #expect(zip(poses, poses.dropFirst()).allSatisfy { $0.azimuth < $1.azimuth })
        #expect(zip(poses, poses.dropFirst()).allSatisfy { $0.elevation < $1.elevation })
        #expect(scene(.ready).pose.distance < 1)
    }

    @Test func theLaunchStartsFarOutInSpace() {
        #expect(OnboardingScene.arrivalPose.distance > 3 * scene(.welcome).pose.distance)
    }

    @Test func aDollyMovesEvenlyInLogDistance() {
        let near = scene(.welcome).pose
        var far = near
        far.distance = near.distance * 4
        #expect(abs(CameraPose.mix(near, far, 0.5).distance - near.distance * 2) < 0.0001)
    }

    // MARK: Welcome

    @Test func welcomeLightsTheBlackHoleWithNothingElseOnTheStage() {
        let welcome = scene(.welcome)
        #expect(welcome.blackHoleLight == 1)
        #expect(welcome.pcStars == 0)
        #expect(welcome.beam == .none)
        #expect(welcome.satellites.isEmpty)
    }

    // MARK: Find

    @Test func findKeepsSonarRunningAndIgnitesEachFoundPC() {
        #expect(scene(.findPC).searching)
        #expect(scene(.findPC, found: 2).searching)
        #expect(scene(.findPC).pcStars == 0)
        #expect(scene(.findPC, found: 2).pcStars == 2)
    }

    @Test func foundPCStarsStopAtEight() {
        #expect(scene(.findPC, found: 20).pcStars == 8)
    }

    // MARK: Pair

    @Test func pairFormsTheBeamUntilThePCPairsThenLocksIt() {
        #expect(scene(.pair).beam == .forming)
        #expect(scene(.pair, paired: true).beam == .locked)
        #expect(scene(.controls, paired: true).beam == .locked)
    }

    // MARK: Controls

    @Test func eachGrantedPermissionPowersItsSatelliteOnTheOrbit() {
        let stage = scene(.controls, permissions: [
            .notifications: .allowed,
            .volumeKeys: .waiting,
            .wifiHelper: .notInThisBuild
        ])
        #expect(stage.satellites == [
            OnboardingSatellite(item: .notifications, powered: true),
            OnboardingSatellite(item: .volumeKeys, powered: false)
        ])
    }

    @Test func controllerButtonsAppearOnlyWhenTheRailOffersThem() {
        #expect(scene(.controls, permissions: [:]).satellites.isEmpty)
        let offered = scene(.controls, permissions: [.controllerButtons: .allowed])
        #expect(offered.satellites == [OnboardingSatellite(item: .controllerButtons, powered: true)])
    }

    @Test func openAtLoginNeverGetsASatellite() {
        #expect(scene(.controls, permissions: [.openAtLogin: .allowed]).satellites.isEmpty)
    }

    @Test func satellitesWaitForTheControlsStep() {
        let permissions: [OnboardingItem: OnboardingItemState] = [.notifications: .allowed]
        #expect(scene(.welcome, permissions: permissions).satellites.isEmpty)
        #expect(scene(.findPC, permissions: permissions).satellites.isEmpty)
        #expect(scene(.pair, permissions: permissions).satellites.isEmpty)
    }

    // MARK: Ready

    @Test func readyHandsTheBlackHoleOffToHomesDeepSpace() {
        let ready = scene(.ready, found: 1, paired: true)
        #expect(ready.blackHoleLight == 0)
        #expect(ready.searching == false)
        #expect(ready.beam == .locked)
        #expect(ready.pcStars == 1)
    }

    // MARK: Motion: camera travel

    @Test func cameraGlidesBetweenStopsInAboutOneAndAHalfSeconds() {
        #expect(OnboardingMotion.travel(elapsed: 0, reduceMotion: false) == 0)
        #expect(OnboardingMotion.travel(elapsed: 1.6, reduceMotion: false) == 1)
        let middle = OnboardingMotion.travel(elapsed: 0.8, reduceMotion: false)
        #expect(abs(middle - 0.5) < 0.01)
        let steps = stride(from: 0.0, through: 1.6, by: 0.05).map {
            OnboardingMotion.travel(elapsed: $0, reduceMotion: false)
        }
        #expect(zip(steps, steps.dropFirst()).allSatisfy { $0 <= $1 })
    }

    @Test func theFallIntoTheHorizonAcceleratesToTheEnd() {
        #expect(OnboardingMotion.fall(elapsed: 0, reduceMotion: false) == 0)
        #expect(OnboardingMotion.fall(elapsed: 2.6, reduceMotion: false) == 1)
        #expect(OnboardingMotion.fall(elapsed: 1.3, reduceMotion: false) < 0.3)
    }

    @Test func afterTheFallTheCameraComesOutIntoCalmSpace() {
        #expect(OnboardingMotion.emerge(sinceFall: 2.6, reduceMotion: false) == 0)
        #expect(OnboardingMotion.emerge(sinceFall: 2.6 + 0.5 + 3.4, reduceMotion: false) == 1)
        #expect(OnboardingMotion.emerge(sinceFall: 0, reduceMotion: true) == 1)
        #expect(OnboardingScene.emergeRest.distance > 100 * StageWorld.shadowRadius / 3)
    }

    @Test func theLaunchFlyInBrakesIntoItsFirstStop() {
        #expect(OnboardingMotion.arrive(elapsed: 0, reduceMotion: false) == 0)
        #expect(OnboardingMotion.arrive(elapsed: 4.6, reduceMotion: false) == 1)
        // Most of the distance is covered early; the landing is long and soft.
        #expect(OnboardingMotion.arrive(elapsed: 1.15, reduceMotion: false) > 0.6)
        #expect(OnboardingMotion.arrive(elapsed: 0.1, reduceMotion: true) == 1)
    }

    @Test func theCameraDriftsSlowlyAndHoldsStillUnderReduceMotion() {
        let drift = OnboardingMotion.drift(elapsed: 10, reduceMotion: false)
        #expect(abs(drift.azimuth) <= 2.4 && abs(drift.elevation) <= 0.9)
        #expect(drift.azimuth != 0)
        let still = OnboardingMotion.drift(elapsed: 10, reduceMotion: true)
        #expect(still.azimuth == 0 && still.elevation == 0)
    }

    @Test func theFirstLightSwellsInOnLaunch() {
        #expect(OnboardingMotion.firstLight(elapsed: 0, reduceMotion: false) == 0)
        #expect(OnboardingMotion.firstLight(elapsed: 3.2, reduceMotion: false) == 1)
        #expect(OnboardingMotion.firstLight(elapsed: 0, reduceMotion: true) == 1)
    }

    @Test func reduceMotionSnapsTheCameraToItsStop() {
        #expect(OnboardingMotion.travel(elapsed: 0.1, reduceMotion: true) == 1)
        #expect(OnboardingMotion.fall(elapsed: 0.1, reduceMotion: true) == 1)
    }

    // MARK: Motion: sonar, ignition, the lock beat, the title

    @Test func sonarRipplesEveryCycleAndStopsUnderReduceMotion() {
        #expect(OnboardingMotion.sonarPhase(elapsed: 0, reduceMotion: false) == 0)
        let mid = OnboardingMotion.sonarPhase(elapsed: 0.9, reduceMotion: false) ?? -1
        #expect(mid > 0 && mid < 1)
        #expect(OnboardingMotion.sonarPhase(elapsed: 1.8, reduceMotion: false) == 0)
        #expect(OnboardingMotion.sonarPhase(elapsed: 0.9, reduceMotion: true) == nil)
    }

    @Test func igniteRisesOverSixTenthsOfASecond() {
        #expect(OnboardingMotion.ignite(elapsed: 0, reduceMotion: false) == 0)
        #expect(OnboardingMotion.ignite(elapsed: 0.6, reduceMotion: false) == 1)
        #expect(OnboardingMotion.ignite(elapsed: 0.1, reduceMotion: true) == 1)
    }

    @Test func lockBeatPeaksQuicklyAndFadesWithinOneAndAHalfSeconds() {
        #expect(OnboardingMotion.lockBeat(sinceLock: 0, reduceMotion: false) == 0)
        #expect(OnboardingMotion.lockBeat(sinceLock: 0.15, reduceMotion: false) > 0.99)
        #expect(OnboardingMotion.lockBeat(sinceLock: 1.5, reduceMotion: false) == 0)
        #expect(OnboardingMotion.lockBeat(sinceLock: 0.15, reduceMotion: true) == 0)
    }

    @Test func shaderTimeFreezesUnderReduceMotion() {
        #expect(OnboardingMotion.shaderTime(elapsed: 12.5, reduceMotion: true) == 0)
        #expect(OnboardingMotion.shaderTime(elapsed: 12.5, reduceMotion: false) == 12.5)
    }
}

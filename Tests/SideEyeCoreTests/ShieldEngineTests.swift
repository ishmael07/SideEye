import Testing
@testable import SideEyeCore

private let fps = 15.0

/// Feeds the same set of faces for `seconds` at 15 fps and returns the last output.
@discardableResult
private func run(
    _ engine: inout ShieldEngine,
    clock: inout Double,
    faces: [FaceSample],
    seconds: Double
) -> ShieldOutput {
    var out = engine.process(faces: faces, at: clock)
    let frames = Int((seconds * fps).rounded())
    for _ in 0..<frames {
        clock += 1 / fps
        out = engine.process(faces: faces, at: clock)
    }
    return out
}

/// Engine that already knows straight-ahead is "looking at the screen".
private func calibrated() -> ShieldEngine {
    ShieldEngine(center: HeadPose(yaw: 0, pitch: 0))
}

private func me(yaw: Double = 0, pitch: Double = 0) -> FaceSample {
    FaceSample(yaw: yaw, pitch: pitch, area: 0.12)
}

@Suite struct LookAway {
    @Test func facingScreenIsClear() {
        var e = calibrated(); var t = 0.0
        let out = run(&e, clock: &t, faces: [me()], seconds: 1)
        #expect(out.level == 0)
        #expect(out.reason == .none)
    }

    @Test func insideComfortZoneIsClear() {
        var e = calibrated(); var t = 0.0
        run(&e, clock: &t, faces: [me()], seconds: 0.5)
        let out = run(&e, clock: &t, faces: [me(yaw: 12)], seconds: 1)
        #expect(out.level == 0)
    }

    @Test func pastFullAngleIsFullyShielded() {
        var e = calibrated(); var t = 0.0
        run(&e, clock: &t, faces: [me()], seconds: 0.5)
        let out = run(&e, clock: &t, faces: [me(yaw: -40)], seconds: 1)
        #expect(out.level == 1)
        #expect(out.reason == .lookingAway)
    }

    @Test func rampIsProgressive() {
        var e = calibrated(); var t = 0.0
        run(&e, clock: &t, faces: [me()], seconds: 0.5)
        // Default comfort 15°, full 30°, hysteresis 2° → active ramp spans 13…30.
        let out = run(&e, clock: &t, faces: [me(yaw: 21.5)], seconds: 2)
        #expect(abs(out.level - 0.5) < 0.02)
    }

    @Test func hysteresisHoldsJustInsideComfortZone() {
        var e = calibrated(); var t = 0.0
        run(&e, clock: &t, faces: [me()], seconds: 0.5)
        run(&e, clock: &t, faces: [me(yaw: 25)], seconds: 1)
        let held = run(&e, clock: &t, faces: [me(yaw: 14)], seconds: 2)
        #expect(held.level > 0)
        let cleared = run(&e, clock: &t, faces: [me(yaw: 10)], seconds: 2)
        #expect(cleared.level == 0)
        // Having cleared, 14° is inside the comfort zone again.
        let again = run(&e, clock: &t, faces: [me(yaw: 14)], seconds: 2)
        #expect(again.level == 0)
    }

    @Test func singleFrameSpikeDoesNotFullyShield() {
        var e = calibrated(); var t = 0.0
        run(&e, clock: &t, faces: [me()], seconds: 0.5)
        t += 1 / fps
        let spike = e.process(faces: [me(yaw: 60)], at: t)
        #expect(spike.level < 1)
    }

    @Test func pitchCountsLessThanYaw() {
        var e = calibrated(); var t = 0.0
        run(&e, clock: &t, faces: [me()], seconds: 0.5)
        let down = run(&e, clock: &t, faces: [me(pitch: 20)], seconds: 1)
        #expect(down.level == 0) // 20° × 0.6 = 12° < 15°
        let wayDown = run(&e, clock: &t, faces: [me(pitch: 55)], seconds: 1)
        #expect(wayDown.level == 1)
    }

    @Test func recenterAdoptsCurrentPose() {
        var e = calibrated(); var t = 0.0
        run(&e, clock: &t, faces: [me()], seconds: 0.5)
        let before = run(&e, clock: &t, faces: [me(yaw: 35)], seconds: 1)
        #expect(before.level == 1)
        e.recenter()
        let after = run(&e, clock: &t, faces: [me(yaw: 35)], seconds: 0.5)
        #expect(after.level == 0)
        let back = run(&e, clock: &t, faces: [me(yaw: 0)], seconds: 1)
        #expect(back.level == 1)
    }

    @Test func disabledTriggerNeverShields() {
        var e = calibrated(); var t = 0.0
        e.config.lookAwayEnabled = false
        run(&e, clock: &t, faces: [me()], seconds: 0.5)
        let out = run(&e, clock: &t, faces: [me(yaw: 50)], seconds: 1)
        #expect(out.level == 0)
    }
}

@Suite struct Absence {
    @Test func leavingShieldsAfterDelay() {
        var e = calibrated(); var t = 0.0
        run(&e, clock: &t, faces: [me()], seconds: 0.5)
        let grace = run(&e, clock: &t, faces: [], seconds: 0.2)
        #expect(grace.level == 0)
        let gone = run(&e, clock: &t, faces: [], seconds: 0.5)
        #expect(gone.level == 1)
        #expect(gone.reason == .absent)
    }

    @Test func graceWindowHoldsLookAwayLevel() {
        var e = calibrated(); var t = 0.0
        run(&e, clock: &t, faces: [me()], seconds: 0.5)
        run(&e, clock: &t, faces: [me(yaw: 40)], seconds: 1)
        // Head turned so far Vision lost the face: must not flash clear.
        t += 1 / fps
        let lost = e.process(faces: [], at: t)
        #expect(lost.level == 1)
    }

    @Test func returningClearsImmediately() {
        var e = calibrated(); var t = 0.0
        run(&e, clock: &t, faces: [me()], seconds: 0.5)
        run(&e, clock: &t, faces: [], seconds: 3)
        let back = run(&e, clock: &t, faces: [me()], seconds: 0.2)
        #expect(back.level == 0)
    }

    @Test func noFaceAtLaunchShields() {
        var e = calibrated(); var t = 0.0
        let out = run(&e, clock: &t, faces: [], seconds: 1)
        #expect(out.level == 1)
        #expect(out.reason == .absent)
    }

    @Test func disabledAbsenceStaysClear() {
        var e = calibrated(); var t = 0.0
        e.config.absentEnabled = false
        run(&e, clock: &t, faces: [me()], seconds: 0.5)
        let out = run(&e, clock: &t, faces: [], seconds: 3)
        #expect(out.level == 0)
    }
}

@Suite struct Intruder {
    private let lurker = FaceSample(yaw: 5, pitch: 0, area: 0.02)

    @Test func secondFaceShieldsAfterConfirmation() {
        var e = calibrated(); var t = 0.0
        run(&e, clock: &t, faces: [me()], seconds: 0.5)
        t += 1 / fps
        let firstFrame = e.process(faces: [me(), lurker], at: t)
        #expect(firstFrame.level == 0) // one frame could be a false positive
        let confirmed = run(&e, clock: &t, faces: [me(), lurker], seconds: 0.4)
        #expect(confirmed.level == 1)
        #expect(confirmed.reason == .intruder)
    }

    @Test func shieldHoldsAfterIntruderLeaves() {
        var e = calibrated(); var t = 0.0
        run(&e, clock: &t, faces: [me(), lurker], seconds: 1)
        let justLeft = run(&e, clock: &t, faces: [me()], seconds: 1)
        #expect(justLeft.level == 1)
        let later = run(&e, clock: &t, faces: [me()], seconds: 1)
        #expect(later.level == 0)
    }

    @Test func tinyBackgroundFaceIsIgnored() {
        var e = calibrated(); var t = 0.0
        let poster = FaceSample(yaw: 0, pitch: 0, area: 0.0005)
        let out = run(&e, clock: &t, faces: [me(), poster], seconds: 2)
        #expect(out.level == 0)
    }

    @Test func intruderOutranksLookingAway() {
        var e = calibrated(); var t = 0.0
        run(&e, clock: &t, faces: [me()], seconds: 0.5)
        let out = run(&e, clock: &t, faces: [me(yaw: 40), lurker], seconds: 1)
        #expect(out.reason == .intruder)
    }

    @Test func primaryIsLargestFaceRegardlessOfOrder() {
        var e = calibrated(); var t = 0.0
        e.config.intruderEnabled = false
        let farTurned = FaceSample(yaw: 50, pitch: 0, area: 0.02)
        let out = run(&e, clock: &t, faces: [farTurned, me()], seconds: 1)
        #expect(out.level == 0)
        #expect(out.faceCount == 2)
    }

    @Test func disabledIntruderStaysClear() {
        var e = calibrated(); var t = 0.0
        e.config.intruderEnabled = false
        let out = run(&e, clock: &t, faces: [me(), lurker], seconds: 2)
        #expect(out.level == 0)
    }
}

@Suite struct Calibration {
    @Test func badFirstFramesDoNotBecomeCenter() {
        var e = ShieldEngine(); var t = 0.0
        // Glancing at a dialog when the camera starts, then settling on the screen.
        run(&e, clock: &t, faces: [me(yaw: 37, pitch: 20)], seconds: 0.3)
        let settled = run(&e, clock: &t, faces: [me(yaw: 3, pitch: 18)], seconds: 2.5)
        #expect(settled.level == 0)
        #expect(settled.calibrating == false)
        #expect(abs((e.center?.yaw ?? 99) - 3) < 1)
        #expect(abs((e.center?.pitch ?? 99) - 18) < 1)
    }

    @Test func neverShieldsForLookingAwayWhileCalibrating() {
        var e = ShieldEngine(); var t = 0.0
        let out = run(&e, clock: &t, faces: [me(yaw: 37)], seconds: 0.5)
        #expect(out.level == 0)
        #expect(out.calibrating)
    }

    @Test func steadyOffAxisPoseIsNotAdopted() {
        var e = ShieldEngine(); var t = 0.0
        let out = run(&e, clock: &t, faces: [me(yaw: 45)], seconds: 3)
        #expect(e.center == nil)
        #expect(out.calibrating)
    }

    @Test func movingHeadIsNotAdopted() {
        var e = ShieldEngine(); var t = 0.0
        for i in 0..<45 {
            t += 1 / fps
            _ = e.process(faces: [me(yaw: i % 2 == 0 ? -15 : 15)], at: t)
        }
        #expect(e.center == nil)
    }

    @Test func absenceStillShieldsWhileUncalibrated() {
        var e = ShieldEngine(); var t = 0.0
        run(&e, clock: &t, faces: [me()], seconds: 0.3)
        let out = run(&e, clock: &t, faces: [], seconds: 1)
        #expect(out.reason == .absent)
    }

    @Test func recenterOverridesAutoCalibration() {
        var e = ShieldEngine(); var t = 0.0
        run(&e, clock: &t, faces: [me(yaw: 45)], seconds: 1)
        e.recenter()
        let out = run(&e, clock: &t, faces: [me(yaw: 45)], seconds: 0.5)
        #expect(out.calibrating == false)
        #expect(out.level == 0)
    }
}

private let left = ShieldEngine.leftTurnYawSign
private let down = ShieldEngine.downTiltPitchSign

@Suite struct Sweep {
    @Test func turningLeftKeepsTheLeftSideReadable() throws {
        var e = calibrated(); var t = 0.0
        let out = run(&e, clock: &t, faces: [me(yaw: left * 22)], seconds: 1)
        #expect(out.level > 0 && out.level < 1)
        let toward = try #require(out.sweepToward)
        #expect(toward.dx < -0.99)
        #expect(abs(toward.dy) < 0.01)
    }

    @Test func turningRightKeepsTheRightSideReadable() throws {
        var e = calibrated(); var t = 0.0
        let out = run(&e, clock: &t, faces: [me(yaw: left * -22)], seconds: 1)
        #expect(try #require(out.sweepToward).dx > 0.99)
    }

    @Test func lookingDownKeepsTheBottomReadable() throws {
        var e = calibrated(); var t = 0.0
        let out = run(&e, clock: &t, faces: [me(pitch: down * 40)], seconds: 1)
        #expect(out.level > 0)
        let toward = try #require(out.sweepToward)
        #expect(toward.dy < -0.99)
        #expect(abs(toward.dx) < 0.01)
    }

    @Test func lookingUpKeepsTheTopReadable() throws {
        var e = calibrated(); var t = 0.0
        let out = run(&e, clock: &t, faces: [me(pitch: down * -40)], seconds: 1)
        #expect(try #require(out.sweepToward).dy > 0.99)
    }

    @Test func diagonalGlanceSweepsDiagonally() throws {
        var e = calibrated(); var t = 0.0
        let out = run(&e, clock: &t, faces: [me(yaw: left * 30, pitch: down * 45)], seconds: 1)
        let toward = try #require(out.sweepToward)
        #expect(toward.dx < -0.3 && toward.dy < -0.3)
        #expect(abs(toward.dx * toward.dx + toward.dy * toward.dy - 1) < 1e-9)
    }

    @Test func smallOffAxisWobbleDoesNotTiltTheSweep() throws {
        var e = calibrated(); var t = 0.0
        let out = run(&e, clock: &t, faces: [me(yaw: left * 25, pitch: 6)], seconds: 1)
        #expect(try #require(out.sweepToward).dy == 0)
    }

    @Test func clearScreenHasNoSweep() {
        var e = calibrated(); var t = 0.0
        let out = run(&e, clock: &t, faces: [me(yaw: 5)], seconds: 1)
        #expect(out.sweepToward == nil)
    }

    @Test func intruderAndAbsenceBlurUniformly() {
        var e = calibrated(); var t = 0.0
        let lurker = FaceSample(yaw: 0, pitch: 0, area: 0.02)
        let intruder = run(&e, clock: &t, faces: [me(yaw: 22), lurker], seconds: 1)
        #expect(intruder.sweepToward == nil)
        let gone = run(&e, clock: &t, faces: [], seconds: 3)
        #expect(gone.sweepToward == nil)
    }

    @Test func losingTheFaceMidTurnKeepsTheSweep() {
        var e = calibrated(); var t = 0.0
        let turned = run(&e, clock: &t, faces: [me(yaw: 22)], seconds: 1)
        t += 1 / fps
        let lost = e.process(faces: [], at: t)
        #expect(lost.level == turned.level)
        #expect(lost.sweepToward == turned.sweepToward)
        #expect(lost.sweepToward != nil)
    }

    @Test func disabledSweepBlursUniformly() {
        var e = calibrated(); var t = 0.0
        e.config.directionalEnabled = false
        let out = run(&e, clock: &t, faces: [me(yaw: 22)], seconds: 1)
        #expect(out.level > 0)
        #expect(out.sweepToward == nil)
    }
}

@Suite struct Smoothing {
    @Test func trackingJitterBarelyMovesTheBlur() {
        var e = calibrated(); var t = 0.0
        run(&e, clock: &t, faces: [me(yaw: 22)], seconds: 1)
        var levels: [Double] = []
        for i in 0..<30 {
            t += 1 / fps
            levels.append(e.process(faces: [me(yaw: i % 2 == 0 ? 20 : 24)], at: t).level)
        }
        #expect(levels.max()! - levels.min()! < 0.08)
    }

    @Test func aRealTurnIsFollowedQuickly() {
        var e = calibrated(); var t = 0.0
        run(&e, clock: &t, faces: [me()], seconds: 1)
        let out = run(&e, clock: &t, faces: [me(yaw: 45)], seconds: 0.35)
        #expect(out.level == 1)
    }
}

@Suite struct Drift {
    @Test func centerFollowsSlowPostureChange() {
        var e = calibrated(); var t = 0.0
        run(&e, clock: &t, faces: [me(yaw: 9, pitch: 12)], seconds: 300)
        #expect(abs((e.center?.yaw ?? 0) - 9) < 1)
        #expect(abs((e.center?.pitch ?? 0) - 12) < 1.5)
    }

    @Test func aGlanceBarelyMovesTheCenter() {
        var e = calibrated(); var t = 0.0
        run(&e, clock: &t, faces: [me(yaw: 12)], seconds: 3)
        #expect(abs(e.center?.yaw ?? 99) < 1)
    }

    @Test func lookingAwayNeverDragsTheCenter() {
        var e = calibrated(); var t = 0.0
        let out = run(&e, clock: &t, faces: [me(yaw: 40)], seconds: 300)
        #expect(e.center == HeadPose(yaw: 0, pitch: 0))
        #expect(out.level == 1)
    }
}

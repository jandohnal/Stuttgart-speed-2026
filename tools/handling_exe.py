"""Extract the constants of the original's driving model from Porsche.exe to JSON.

The model (docs/formats/sim.md, section "Jízdní model originálu") is reimplemented in
game/scripts/original_handling.gd. Its tuning constants live in the exe's data section; this
tool reads them by address from the local exe (official patch of 5 June 2000, D-023) and writes
them to decomposed/, so the repository holds only the addresses and the names.

Output JSON:
    {"exe": "<file name>", "constants": {"<name>": value, ...},
     "surface_grip": {"dry": [[road, rain, slick] per surface], "wet": [...]},
     "slide_divisor": [per tyre type], "downshift_blip": {"light": [...], "braking": [...]}}

Usage:
    python3 tools/handling_exe.py sources/Porsche.exe decomposed/GameData/Simulation/handling.json
"""
import json
import os
import sys

from pe_exe import Exe

# name: address of an f32 in the exe's data section (functions named in docs/formats/sim.md).
CONSTANTS = {
    # step 0x49F160 and integration
    "tick": 0x5B24B8,  # s per model step
    "gravity": 0x5B25BC,  # m/s2 in the grip formula
    "velocity_gain": 0x5B2644,  # tick rate: velocity -> acceleration that cancels it in one tick
    "velocity_share": 0x5B2448,  # (negative) share of that the tyres act on
    "yaw_gain": 0x5B4A74,  # yaw rate change per tick per unit of yaw moment
    "yaw_gain_simple": 0x5B24B8,  # same in the simplified mode
    "lever_scale": 0x5B4A2C,  # half wheelbase (m) x this x angle_turn = yaw lever
    "angle_turn": 0x5B26B0,  # angle units per turn
    "yaw_slip_speed": 0x5B241C,  # m/s where the yaw lever scaling changes
    "yaw_slip_fast_add": 0x5B26F4, "yaw_slip_fast_mul": 0x5B4A84,
    "yaw_slip_slow_add": 0x5B2408, "yaw_slip_slow_mul": 0x5B4A2C,
    # steering 0x49F160, 0x49DD20
    "steer_input_scale": 0x5B4A78,  # 1 / full input
    "steer_low_speed": 0x5B2408,  # m/s under which the lock grows
    "steer_low_base": 0x5B36E8, "steer_low_per_ms": 0x5B4A2C,
    "steer_lock_cap": 0x5B2470,  # angle units
    "steer_high_speed": 0x5B26D4,  # m/s above which the angle is divided by speed
    "steer_high_div": 0x5B4A84,
    "steer_damage": 0x5B4A7C,  # per damage unit of the front wheel
    "steer_unit": 0x5B2640,  # turns per angle unit
    "camber_pull": 0x5B2608,  # steering units per m/s2 of the road's side slope
    "damage_pull": 0x5B2468,  # steering units per damage unit of front left against right
    "still_speed": 0x5B23F4,  # m/s under which the automatic selects reverse or first
    # loads and grip 0x4A1900
    "transfer_scale": 0x5B4A9C,  # (negative) 1 / g
    "transfer_long": 0x5B4A98,  # (negative)
    "transfer_lat": 0x5B23F4,
    "transfer_slip_cut": 0x5B241C,  # transfer under throttle shrinks by this x slip
    "downforce_speed": 0x5B2400,  # m/s from which downforce acts
    "simple_front_grip": 0x5B27A4,
    # wheel forces 0x4A20D0, 0x4A1DC0, 0x4A1C70
    "drive_throttle_limit": 0x5B2468,  # over this throttle a driven wheel may spin against the motion
    "rear_angle_full": 0x5B2580,  # angle units for the full side force of a rear wheel
    "front_angle_max": 0x5B26A8,  # angle units, front side force grows up to here
    "front_angle_gain": 0x5B49B0,  # front side force per angle unit, x capacity
    "slow_speed_sum": 0x5B2644,  # under this |lat| + |long| the front force only stops the wheel
    "lock_capacity_margin": 0x5B26A8,  # no ABS: a braked wheel locks under 2 x (this - capacity) m/s
    "lock_speed": 0x5B2400,  # m/s
    "abs_pulse_speed": 0x5B24DC,  # m/s, with ABS under it the wheel locks one tick in four
    "handbrake_speed": 0x5B23F0,  # m/s
    "long_combine": 0x5B25E8,  # longitudinal force share in the friction circle
    "long_combine_simple": 0x5B23F0,
    "minor_combine": 0x5B2468,  # smaller force's share in the friction circle
    "damage_grip": 0x5B3284,  # per damage unit
    "skid_keep": 0x5B2600, "skid_rear": 0x5B240C, "skid_front": 0x5B23F0, "skid_mix": 0x5B2468,
    "skid_lock": 0x5B49B4,
    "tc_slip": 0x5B2638,  # traction control lets the rear slide over this slip
    "slide_min": 0x5B27A8,
    "simple_front_side": 0x5B2480,
    # engine and gearbox 0x49E440, 0x49DAF0, loader 0x49C6C0 / 0x49CB50
    "rpm_rise": 0x5B4A60, "rpm_fall": 0x5B2484, "rpm_target_margin": 0x5B242C,
    "shift_drop_low": 0x5B242C, "shift_drop_high": 0x5B2484,
    "torque_step": 0x5B4A30,  # 1 / rpm per curve point
    "engine_damage": 0x5B4A64,  # per damage unit
    "sync_window": 0x5B4A58, "sync_redline_margin": 0x5B2524,
    "spin_rpm": 0x5B4A60,
    "creep_back": 0x5B2444, "creep_forward": 0x5B2604,
    "traction_force": 0x5B243C, "traction_base": 0x5B242C, "traction_base_awd": 0x5B3D60,
    "throttle_byte": 0x5B4A54, "throttle_floor": 0x5B25F0, "spin_fall": 0x5B49D4,
    "spin_flag_share": 0x5B272C,
    "sync_step": 0x5B2484, "sync_band": 0x5B4A4C,
    "over_rev": 0x5B24E0,
    "engine_brake_damage": 0x5B3714, "engine_brake_damage_cap": 0x5B2400,
    "rev_rate": 0x5B4A50,
    "rpm_cap": 0x5B3F64,
    "limiter_bounce": 0x5B251C,  # rpm over the redline the limiter drops the revs to
    "misfire_brake": 0x5B2404,
    "auto_up": 0x5B25E8, "auto_up_spread": 0x5B2604, "auto_down": 0x5B24E8,
    "auto_engine_vs_wheel": 0x5B2480, "auto_slip": 0x5B2604,
    "rpm_per_minute": 0x5B26F0, "rim_mm": 0x5B4A40, "sidewall_scale": 0x5B3714, "circumference": 0x5B4A3C,
    "force_scale": 0x5B49B4, "manual_bonus": 0x5B3F90,
    "mph": 0x5B4A28, "percent": 0x5B3CA0, "milli": 0x5B3060,
    # 0x49F160 end: slowing down
    "race_grip": 0x5B2464, "race_yaw_slow": 0x5B3F6C, "neutral_fast_speed": 0x5B2470,
    # slope 0x49F0C0
    "slope_long": 0x5B2438, "slope_lat": 0x5B4A68, "slope_steep": 0x5B4A6C,
    # body motion (visual)
    "pitch_keep": 0x5B25E8, "pitch_take": 0x5B2604, "roll_keep": 0x5B260C, "roll_take": 0x5B2468,
}
SURFACES = 16  # rows of the surface tables, 3 tyre types each
SURFACE_DRY, SURFACE_WET = 0x5D0D50, 0x5D0E4C
SLIDE_DIVISOR = 0x5D0F58  # per tyre type: share of the grip a sliding tyre keeps is 1 - 1 / divisor
BLIP_LIGHT, BLIP_BRAKING = 0x5D0C70, 0x5D0C90  # rpm added per downshift, by target gear


def extract(path):
    exe = Exe(path)
    rows = lambda va: [exe.f32s(va + 12 * s, 3) for s in range(SURFACES)]
    return {
        "exe": os.path.basename(path),
        "constants": {name: exe.f32(va) for name, va in CONSTANTS.items()},
        "surface_grip": {"dry": rows(SURFACE_DRY), "wet": rows(SURFACE_WET)},
        "slide_divisor": exe.f32s(SLIDE_DIVISOR, 3),
        "downshift_blip": {"light": exe.f32s(BLIP_LIGHT, 8), "braking": exe.f32s(BLIP_BRAKING, 8)},
    }


def main(exe_path, target):
    data = extract(exe_path)
    os.makedirs(os.path.dirname(target) or ".", exist_ok=True)
    with open(target, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=1)
    print("%d constants -> %s" % (len(data["constants"]), target))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])

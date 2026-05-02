# Initial State Red Flags Analysis
**Date**: 2026-04-16  
**Analysis Period**: 2022-11-01 00:05:00 to 2022-11-01 04:00:00  
**Initial State Timestamp (t=0)**: 2022-10-31 23:55:00  
**Total Scheduled Units**: 248

---

## Executive Summary

Analysis of the initial state (P_{i,t=0}) for the optimization model revealed **four critical data quality issues** that must be addressed before proceeding with unit commitment and economic dispatch optimization:

1. **57 units (23%) lack constraint data** due to null technology descriptors
2. **SA1 region has unusually low capacity factor** (79% offline)
3. **159 units (64%) require cold start** from zero power
4. **Pumped hydro loads misclassified** as generators

**Action Taken**: Filtered out 57 problematic units (mostly virtual/demand-response) with minimal power impact (~2.33 MW).

---

## 🔴 Red Flag #1: Units Missing Constraint Data (CRITICAL)

### Issue Description
- **57 scheduled units (23% of total)** have `null` in `TECHNOLOGYTYPEDESCRIPTOR`
- These units cannot be matched to the `nsw_generators_constraints` table
- Without technology type, optimizer cannot apply:
  - Ramping rate limits (MIN/MAX_RAMP_RATE_PROXY)
  - Minimum stable generation levels
  - Startup time constraints
  - Minimum up/down time requirements

### Affected Unit Types

| Unit Pattern | Count | Description | Power at t=0 |
|-------------|-------|-------------|-------------|
| `RT_*` | 24 | Regional trading/tariff units | 0.00 MW |
| `DRX*` | 17 | Demand response units | 0.00 MW |
| `*BL1` | 9 | Battery load units | 2.33 MW |
| `PUMP*`, `SHPUMP` | 3 | Pumped hydro loads | 0.00 MW |
| Technology = `-` | 4 | Undefined technology | 0.00 MW |
| **TOTAL** | **57** | | **~2.33 MW** |

### Regional Distribution

| Region | Null Tech Units | Total Power (MW) |
|--------|----------------|------------------|
| NSW1 | 14 | 0.0025 |
| QLD1 | 4 | 0.00 |
| SA1 | 14 | 0.987 |
| TAS1 | 1 | 0.00 |
| VIC1 | 21 | 1.34 |

### Impact Assessment
- **Optimization Impact**: HIGH (cannot constrain these units)
- **Power Impact**: LOW (only 2.33 MW total, mostly offline)
- **Unit Type**: Mostly virtual/non-physical units (demand response, trading placeholders)

### Recommendation: ✅ EXCLUDE FROM OPTIMIZATION
**Rationale**:
- These are primarily administrative/virtual units, not physical generators
- Total power contribution negligible (~0.01% of system capacity)
- Excluding them eliminates constraint data gaps without material impact
- Physical generators all have proper technology mappings

### Alternative Options (Not Recommended)
- **Option B**: Create default "UNKNOWN" technology with conservative constraints
  - Risk: May over/under-constrain units inappropriately
- **Option C**: Manually research and map each DUID
  - Cost: High effort, low return given minimal power contribution

---

## 🟡 Red Flag #2: SA1 Region Low Capacity Factor

### Issue Description
- **48 scheduled units** in SA1 region
- Only **136.9 MW** total output at t=0
- **38 units offline** (79% of fleet)
- Only **10 units running**

### Context & Analysis
- **Time of day**: 23:55:00 (overnight low-demand period)
- **SA1 characteristics**: Highest renewable penetration in NEM
  - High wind generation overnight
  - High solar during day (but not at night)
  - Thermal units economically displaced by renewables
- **Comparison to other regions** at t=0:
  - NSW1: 5,236 MW (51 units)
  - QLD1: 5,702 MW (58 units)
  - VIC1: 4,682 MW (65 units)
  - TAS1: 689 MW (26 units)

### Assessment: ✅ LIKELY NORMAL BEHAVIOR
**Rationale**:
- Consistent with SA1's renewable-heavy generation mix
- Overnight period = low demand + high wind
- Thermal generation economically dispatched down/off
- Units available for commitment if needed during optimization period

### Optimization Implications
- Optimizer may need to commit multiple SA1 units from cold start
- Ensure startup time constraints properly enforced
- Verify demand forecast justifies unit commitments

### Validation Recommended
- Compare to historical SA1 capacity factors for similar time periods
- Verify non-scheduled generation (wind/solar) was high at this time

---

## 🟡 Red Flag #3: High Cold Start Requirement

### Issue Description
- **159 units starting from zero power** (64% of scheduled fleet)
- Units must respect startup constraints when committed

### Regional Breakdown

| Region | Units at Zero | Total Scheduled | % Offline |
|--------|---------------|-----------------|----------|
| NSW1 | 34 | 51 | 67% |
| QLD1 | 30 | 58 | 52% |
| SA1 | 38 | 48 | 79% |
| TAS1 | 12 | 26 | 46% |
| VIC1 | 45 | 65 | 69% |
| **TOTAL** | **159** | **248** | **64%** |

### Optimization Requirements

#### Must Implement:
1. **Binary variables** for unit on/off state
2. **Startup time constraints**:
   - Units at zero cannot generate full power in first interval
   - Must respect `STARTUP_TIME` from constraints table
3. **Minimum up/down time**:
   - `MIN_UPTIME`: Once started, must stay on
   - `MIN_DOWNTIME`: Once stopped, must stay off
4. **Ramping from zero**:
   - First interval constraint: `|P_{i,t=1} - 0| ≤ MAX_RAMP_RATE × 5 min`
   - May need startup ramp rate separate from normal ramp rate

### Assessment: ✅ MANAGEABLE
**Rationale**:
- This is normal for overnight low-demand period
- Optimization model must handle unit commitment (already planned)
- Constraint data available for technology types

### Recommended Actions
- Implement binary commitment variables in optimization model
- Apply startup time as constraint, not just ramping limit
- Consider pre-committing baseload units for feasibility
- Validate that demand increase justifies cold starts

---

## 🟠 Red Flag #4: Pumped Hydro Loads Misclassified

### Issue Description
- **3 units** have technology descriptor = `-`:
  - `SHPUMP` (NSW1) - Shoalhaven pumped storage pumping
  - `PUMP1` (QLD1) - Wivenhoe pumped storage pumping
  - `PUMP2` (QLD1) - Wivenhoe pumped storage pumping
- All show 0 MW at t=0
- All marked as "SCHEDULED"

### Technical Context
- **Pumping loads consume power** (negative generation)
- Different from generating mode of pumped hydro
- Should these be in generation optimization or load optimization?

### Assessment: ⚠️ REQUIRES CLARIFICATION
**Questions**:
1. Should pumping loads be optimized separately from generation?
2. Are these loads flexible (can shift pumping time)?
3. Should they appear as negative generation or separate load?

### Recommended Actions
- **Short-term**: Exclude from generation optimization (currently 0 MW)
- **Long-term**: Clarify pumped storage treatment:
  - Option A: Model as flexible load (separate optimization)
  - Option B: Include as negative generation with pumping constraints
  - Option C: Model pumped storage as single asset with generation/pumping modes

---

## Data Quality Summary

### Units by Constraint Availability

| Category | Count | % of Total | Total Power (MW) | Action |
|----------|-------|-----------|------------------|--------|
| **Valid constraints** | 191 | 77% | 16,344 | ✅ Include in optimization |
| **Missing constraints** | 57 | 23% | 2.33 | ❌ Exclude from optimization |
| **Total scheduled** | 248 | 100% | 16,346 | |

### Power Impact of Filtering
- **Total initial power**: 16,346.3 MW
- **Excluded power**: 2.33 MW
- **Optimization dataset**: 16,344.0 MW (99.99% coverage)

---

## Implementation: Filtered Dataset

### Filtering Criteria
Exclude units where `TECHNOLOGYTYPEDESCRIPTOR IS NULL OR TECHNOLOGYTYPEDESCRIPTOR = '-'`

### Resulting Dataset
- **191 scheduled units** with complete constraint data
- **All physical generators** retained
- **Virtual/administrative units** excluded
- **Pumped hydro loads** excluded

### Output Table
`energy_endava_193.default.nsw_generator_initial_state_clean`

**Schema**:
- `DUID` - Generator unit ID
- `SETTLEMENTDATE` - Initial state timestamp (2022-10-31 23:55:00)
- `INITIAL_POWER` - Power output at t=0 (MW)
- `SCHEDULE_TYPE` - "SCHEDULED"
- `TECHNOLOGYTYPEDESCRIPTOR` - Technology type (NOT NULL)
- `REGIONID` - NEM region (NSW1, QLD1, SA1, TAS1, VIC1)

---

## Next Steps

### Immediate Actions (Completed)
- [x] Document red flags and analysis
- [x] Filter out 57 units with missing constraints
- [x] Create clean initial state table for optimization

### Before Building Optimization Model
- [ ] Validate SA1 capacity factor against historical data
- [ ] Confirm pumped storage treatment approach
- [ ] Verify constraint data completeness for remaining 191 units
- [ ] Map DUID-level ramp rates from dictionary (if available)

### Optimization Model Requirements
- [ ] Implement binary commitment variables
- [ ] Apply startup time constraints
- [ ] Apply minimum up/down time constraints
- [ ] Implement ramping constraints with initial state anchor
- [ ] Handle cold starts (159 units at zero)

---

## References

### Data Sources
- **Initial state data**: `energy_endava_193.default.nsw_generator_initial_state`
- **Constraint data**: `energy_endava_193.default.nsw_generators_constraints`
- **Dictionary**: `energy_endava_193.default.nsw_dictionary_mapped`
- **Analysis notebook**: `03_ingest_gold`

### Analysis Date
2026-04-16

### Contact
Data Engineering Team - Endava Energy Project 193
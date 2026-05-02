# Unit Commitment & Economic Dispatch Optimization Model
**Mathematical Formulation**

**Date**: 2026-04-16  
**Model Type**: Mixed-Integer Linear Programming (MILP)  
**Solver**: Pyomo or PuLP (Python-based)  
**Time Horizon**: 2022-11-01 00:05:00 to 04:00:00 (48 intervals × 5 minutes)  
**Optimization Dataset**: 191 scheduled generators across 5 NEM regions

---

## Table of Contents
1. [Sets and Indices](#sets-and-indices)
2. [Parameters](#parameters)
3. [Decision Variables](#decision-variables)
4. [Objective Function](#objective-function)
5. [Constraints](#constraints)
6. [Data Mapping](#data-mapping)
7. [Missing Data & Questions](#missing-data--questions)
8. [Implementation Notes](#implementation-notes)

---

## 1. Sets and Indices

### Sets
- **I**: Set of all generators (DUIDs) in optimization  
  `I = {DUID | DUID in nsw_generator_initial_state_clean}`  
  |I| = 191 units

- **T**: Set of time intervals  
  `T = {1, 2, 3, ..., 48}` (5-minute intervals)  
  First interval: t=1 corresponds to 2022-11-01 00:05:00

- **R**: Set of regions  
  `R = {NSW1, QLD1, SA1, TAS1, VIC1}`

- **I_r**: Set of generators in region r  
  `I_r = {i ∈ I | REGIONID_i = r}`

- **I_thermal**: Set of thermal/gas generators requiring binary commitment  
  `I_thermal = {i ∈ I | TECHNOLOGYTYPEDESCRIPTOR_i ∈ {STEAM SUB-CRITICAL, STEAM SUPER CRITICAL, OPEN CYCLE GAS TURBINES (OCGT), COMBINED CYCLE GAS TURBINE (CCGT), COMPRESSION RECIPROCATING ENGINE}}`

- **I_renewable**: Set of renewable generators (no commitment binary needed)  
  `I_renewable = {i ∈ I | TECHNOLOGYTYPEDESCRIPTOR_i ∈ {HYDRO - GRAVITY, RUN OF RIVER, PUMP STORAGE}}`

- **I_semi**: Set of semi-scheduled renewable generators (have SCADA cap)  
  `I_semi = {i ∈ I | SCHEDULE_TYPE_i = SEMI-SCHEDULED}`  
  *(Note: After filtering, only SCHEDULED units remain in clean dataset)*

### Indices
- **i**: Generator index (i ∈ I)
- **t**: Time interval index (t ∈ T)
- **r**: Region index (r ∈ R)

---

## 2. Parameters

### Generator Characteristics
| Parameter | Description | Source Table | Column | Units |
|-----------|-------------|--------------|--------|-------|
| Pᵢ₀ | Initial power output at t=0 | `nsw_generator_initial_state_clean` | `INITIAL_POWER` | MW |
| Pᵢᵐⁱⁿ | Minimum stable generation | `nsw_generators_constraints` | `MIN_STABLE_GENERATION` | MW |
| Pᵢᵐᵃˣ | Maximum capacity | `nsw_dictionary_mapped` | `MAXCAPACITY` | MW |
| Rᵢᵘᵖ | Maximum ramp rate (up/down) | `nsw_generators_constraints` | `MAX_RAMP_RATE_PROXY` | MW/min |
| SUᵢ | Startup time | `nsw_generators_constraints` | `STARTUP_TIME` | minutes |
| UTᵢ | Minimum uptime | `nsw_generators_constraints` | `MIN_UPTIME` | minutes |
| DTᵢ | Minimum downtime | `nsw_generators_constraints` | `MIN_DOWNTIME` | minutes |
| Cᵢ | Marginal cost (proxy) | **[MISSING - User Input Required]** | Technology-based | $/MWh |
| SCADAᵢₜ | Available capacity for semi-scheduled | `nsw_scada_peak_2022` | `SCADAVALUE` | MW |

### System Parameters
| Parameter | Description | Source Table | Column | Units |
|-----------|-------------|--------------|--------|-------|
| Dᵣₜ | Residual demand target | `residual_demand` | `RESIDUAL_DEMAND` | MW |

### Time Discretization
- **Δt**: Time step duration = 5 minutes

---

## 3. Decision Variables

### Continuous Variables
**Pᵢₜ**: Power output of generator i at time t  
- Type: Continuous  
- Domain: [0, Pᵢᵐᵃˣ]  
- Units: MW  
- Dimensions: |I| × |T| = 191 × 48 = 9,168 variables

### Binary Variables
**uᵢₜ**: Commitment status of generator i at time t  
- Type: Binary {0, 1}  
- Domain: {0 = offline, 1 = online}  
- Applies to: i ∈ I_thermal only  
- Dimensions: |I_thermal| × |T|  
  - Thermal units: ~130 units × 48 intervals = ~6,240 variables

**Startup/Shutdown Indicators** (optional, for startup cost modeling):
- **vᵢₜ**: Startup indicator (vᵢₜ = 1 if unit i starts up at t)  
- **wᵢₜ**: Shutdown indicator (wᵢₜ = 1 if unit i shuts down at t)

---

## 4. Objective Function

### Minimize Total Operating Cost

```
Minimize Z = Σᵢ₊ᴵ Σₜ₊ᵀ (Cᵢ × Pᵢₜ × Δt)
```

Where:
- **Cᵢ**: Marginal cost of generator i ($/MWh)
- **Pᵢₜ**: Power output (MW)
- **Δt**: Time step (5 min = 1/12 hour)

### Proxy Cost Structure **[USER INPUT REQUIRED]**

Suggested costs by technology type (merit order dispatch):

| Technology Type | Typical Fuel | Suggested Proxy Cost ($/MWh) | Units in Dataset |
|-----------------|--------------|------------------------------|------------------|
| HYDRO - GRAVITY | Water | **$0 - $5** | 34 |
| RUN OF RIVER | Water | **$0 - $5** | 6 |
| PUMP STORAGE | Water | **$0 - $5** | 2 |
| STEAM SUB-CRITICAL | Coal | **$30 - $50** | 46 |
| STEAM SUPER CRITICAL | Coal | **$35 - $55** | 6 |
| COMBINED CYCLE GAS TURBINE (CCGT) | Gas | **$80 - $120** | 12 |
| OPEN CYCLE GAS TURBINES (OCGT) | Gas | **$150 - $250** | 65 |
| BATTERY | Stored energy | **$100 - $150** | 14 |
| COMPRESSION RECIPROCATING ENGINE | Diesel/Gas | **$200 - $300** | 1 |
| AGGREGATED | Mixed | **$50** | 5 |

**Note**: These are proxy costs to enforce economic dispatch order. Actual market prices are much more complex.

### Extended Objective (Optional)
```
Minimize Z = Σᵢ Σₜ (Cᵢ × Pᵢₜ × Δt) + Σᵢ₊ᴵₜʰᵉʳᵐᵃˡ Σₜ (Cᵢˢᵘ × vᵢₜ)
```
Where:
- **Cᵢˢᵘ**: Startup cost for unit i **[MISSING DATA]**
- **vᵢₜ**: Startup indicator

---

## 5. Constraints

### 5.1 System Balance (Power Supply = Demand)

**Per Region, Per Time:**
```
Σᵢ₊ᴵᵣ Pᵢₜ = Dᵣₜ    ∀ r ∈ R, t ∈ T
```

Where:
- **I_r**: Generators in region r
- **Dᵣₜ**: Residual demand in region r at time t (from `residual_demand` table)

**Data Source:**
- Table: `energy_endava_193.default.residual_demand`
- Key: (`REGIONID`, `SETTLEMENTDATE`)
- Value: `RESIDUAL_DEMAND` (MW)

---

### 5.2 Generation Limits

#### 5.2.1 For Thermal/Gas Units (with Commitment)
```
Pᵢᵐⁱⁿ × uᵢₜ ≤ Pᵢₜ ≤ Pᵢᵐᵃˣ × uᵢₜ    ∀ i ∈ I_thermal, t ∈ T
```

Interpretation:
- If uᵢₜ = 0 (offline): Pᵢₜ = 0
- If uᵢₜ = 1 (online): Pᵢᵐⁱⁿ ≤ Pᵢₜ ≤ Pᵢᵐᵃˣ

#### 5.2.2 For Renewable Units (No Commitment Binary)
```
0 ≤ Pᵢₜ ≤ Pᵢᵐᵃˣ    ∀ i ∈ I_renewable, t ∈ T
```

**Data Sources:**
- **Pᵢᵐⁱⁿ**: `nsw_generators_constraints.MIN_STABLE_GENERATION` (by `TECHNOLOGYTYPEDESCRIPTOR`)
- **Pᵢᵐᵃˣ**: `nsw_dictionary_mapped.MAXCAPACITY` (by `DUID`)

---

### 5.3 Ramping Constraints

#### 5.3.1 Standard Ramping (Between Consecutive Intervals)
```
|Pᵢₜ - Pᵢₜ₋₁| ≤ Rᵢᵘᵖ × Δt    ∀ i ∈ I, t ∈ {2, 3, ..., T}
```

Linearized form (for LP solver):
```
Pᵢₜ - Pᵢₜ₋₁ ≤ Rᵢᵘᵖ × Δt
Pᵢₜ₋₁ - Pᵢₜ ≤ Rᵢᵘᵖ × Δt
```

Where:
- **Rᵢᵘᵖ**: Maximum ramp rate (MW/min) from `nsw_generators_constraints.MAX_RAMP_RATE_PROXY`
- **Δt**: 5 minutes

#### 5.3.2 Initial State Ramping (t=1 anchor)
```
|Pᵢ₁ - Pᵢ₀| ≤ Rᵢᵘᵖ × Δt    ∀ i ∈ I
```

Where:
- **Pᵢ₀**: Initial power from `nsw_generator_initial_state_clean.INITIAL_POWER`

**Data Sources:**
- **Rᵢᵘᵖ**: `nsw_generators_constraints.MAX_RAMP_RATE_PROXY` (MW/min)
- **Pᵢ₀**: `nsw_generator_initial_state_clean.INITIAL_POWER` (MW)

---

### 5.4 Renewable Capacity Constraint (Semi-Scheduled)

**For semi-scheduled units** (if any remain after filtering):
```
Pᵢₜ ≤ SCADAᵢₜ    ∀ i ∈ I_semi, t ∈ T
```

Where:
- **SCADAᵢₜ**: Actual available generation from `nsw_scada_peak_2022.SCADAVALUE`

**Note**: After filtering for clean initial state, we only have SCHEDULED units. This constraint may not apply unless we include SEMI-SCHEDULED units separately.

---

### 5.5 Minimum Up Time

**If a unit starts up, it must stay online for at least UTᵢ intervals:**

```
Σᵗ₌ₜ⁼ᵘᵗ₌ₜ⁺⌈ᵘᵀᵢ/Δᵗ⌉₋₁ uᵢᵗ ≥ ⌈UTᵢ/Δt⌉ × (uᵢₜ - uᵢₜ₋₁)    ∀ i ∈ I_thermal, t ∈ {2, ..., T}
```

Simplified form (for small time horizons):
```
If uᵢₜ - uᵢₜ₋₁ = 1 (startup at t), then uᵢᵗ = 1 for τ ∈ {t, t+1, ..., t+⌈UTᵢ/Δt⌉-1}
```

**Data Source:**
- **UTᵢ**: `nsw_generators_constraints.MIN_UPTIME` (minutes)
- Convert to intervals: ⌈UTᵢ / 5⌉

---

### 5.6 Minimum Down Time

**If a unit shuts down, it must stay offline for at least DTᵢ intervals:**

```
Σᵗ₌ₜ⁼ᵘᵗ₌ₜ⁺⌈ᴷᵀᵢ/Δᵗ⌉₋₁ (1 - uᵢᵗ) ≥ ⌈DTᵢ/Δt⌉ × (uᵢₜ₋₁ - uᵢₜ)    ∀ i ∈ I_thermal, t ∈ {2, ..., T}
```

Simplified form:
```
If uᵢₜ₋₁ - uᵢₜ = 1 (shutdown at t), then uᵢᵗ = 0 for τ ∈ {t, t+1, ..., t+⌈DTᵢ/Δt⌉-1}
```

**Data Source:**
- **DTᵢ**: `nsw_generators_constraints.MIN_DOWNTIME` (minutes)
- Convert to intervals: ⌈DTᵢ / 5⌉

---

### 5.7 Startup Time Constraint

**Units starting from zero (cold start) cannot reach full power immediately:**

```
If uᵢ₀ = 0 and uᵢ₁ = 1, then Pᵢ₁ ≤ min(Rᵢᵘᵖ × SUᵢ, Pᵢᵐᵃˣ)
```

Where:
- **uᵢ₀**: Initial commitment state (1 if Pᵢ₀ > 0, else 0)
- **SUᵢ**: Startup time (minutes)

**Alternative**: Enforce ramping constraint from zero:
```
Pᵢ₁ ≤ Rᵢᵘᵖ × Δt    if Pᵢ₀ = 0
```

**Data Sources:**
- **SUᵢ**: `nsw_generators_constraints.STARTUP_TIME` (minutes)
- **Pᵢ₀**: `nsw_generator_initial_state_clean.INITIAL_POWER`

---

### 5.8 Startup/Shutdown Indicator Constraints (Optional)

**If using startup costs:**

```
vᵢₜ ≥ uᵢₜ - uᵢₜ₋₁    ∀ i ∈ I_thermal, t ∈ T
wᵢₜ ≥ uᵢₜ₋₁ - uᵢₜ    ∀ i ∈ I_thermal, t ∈ T
```

---

### 5.9 Non-Negativity and Binary Constraints

```
Pᵢₜ ≥ 0    ∀ i ∈ I, t ∈ T
uᵢₜ ∈ {0, 1}    ∀ i ∈ I_thermal, t ∈ T
```

---

## 6. Data Mapping

### Tables and Joins

#### Generator Parameters
```python
# Primary key: DUID
genset = nsw_generator_initial_state_clean.join(
    nsw_dictionary_mapped.select("DUID", "MAXCAPACITY", "REGIONID"),
    on="DUID"
).join(
    nsw_generators_constraints,
    on="TECHNOLOGYTYPEDESCRIPTOR"
)

# Extract:
# - P_i0: INITIAL_POWER
# - P_imax: MAXCAPACITY
# - P_imin: MIN_STABLE_GENERATION
# - R_i: MAX_RAMP_RATE_PROXY
# - UT_i: MIN_UPTIME
# - DT_i: MIN_DOWNTIME
# - SU_i: STARTUP_TIME
# - REGIONID: Region assignment
```

#### Demand Target
```python
# Key: (REGIONID, SETTLEMENTDATE)
demand = residual_demand.select(
    "REGIONID", "SETTLEMENTDATE", "RESIDUAL_DEMAND"
)

# Pivot to get D_rt for each (region, time interval)
```

#### Renewable Availability (if needed)
```python
# Key: (DUID, SETTLEMENTDATE)
scada = nsw_scada_peak_2022.select(
    "DUID", "SETTLEMENTDATE", "SCADAVALUE"
)

# Use for semi-scheduled renewable cap constraint
```

---

## 7. Missing Data & Questions

### ❌ **CRITICAL: Missing Data**

#### 7.1 Proxy Costs (Cᵢ)
**Status**: ❌ **NOT AVAILABLE**

**Question**: What proxy costs should we assign to each technology type?

**Suggestion**: Use the merit order table above, or provide custom costs:
- Hydro: $0-5/MWh
- Coal: $30-50/MWh
- Gas CCGT: $80-120/MWh
- Gas OCGT: $150-250/MWh
- Battery: $100-150/MWh

**Decision Required**: 
- [ ] Accept suggested proxy costs?
- [ ] Provide custom cost table?

---

#### 7.2 Startup Costs (Cᵢˢᵘ)
**Status**: ❌ **NOT AVAILABLE**

**Question**: Should we include startup costs in the objective function?

If yes:
- Typical values: $500-5000 per start for coal, $100-500 for gas
- Requires startup indicator variables (vᵢₜ)

**Decision Required**:
- [ ] Include startup costs? (adds complexity)
- [ ] Ignore startup costs? (simplified model)

---

#### 7.3 Ramp Rate Data Source
**Status**: ⚠️ **AMBIGUOUS**

**Issue**: Two sources for ramp rates:
1. `nsw_dictionary_mapped.RAMP_UP_RATE` and `RAMP_DOWN_RATE` (DUID-specific)
2. `nsw_generators_constraints.MAX_RAMP_RATE_PROXY` (technology-level)

**Question**: Which ramp rate should we use?

**Options**:
- **Option A**: Use DUID-specific rates from dictionary (more accurate, but may have missing values)
- **Option B**: Use technology-level proxy (consistent, but less accurate)
- **Option C**: Use dictionary where available, fall back to proxy

**Decision Required**:
- [ ] Use DUID-specific ramp rates?
- [ ] Use technology proxy ramp rates?
- [ ] Hybrid approach?

---

#### 7.4 Missing MAXCAPACITY Values
**Status**: ⚠️ **POTENTIAL ISSUE**

**Question**: Do all 191 units have MAXCAPACITY in the dictionary?

**Action Required**:
- [ ] Verify MAXCAPACITY completeness
- [ ] If missing, how to estimate? (Use nameplate capacity, or exclude unit?)

---

#### 7.5 Battery Modeling
**Status**: ⚠️ **UNCLEAR**

**Issue**: 14 battery units in dataset. Batteries can:
- Discharge (positive Pᵢₜ)
- Charge (negative Pᵢₜ?)

**Question**: Should batteries be modeled with:
1. **Discharge only** (treat like generators, Pᵢₜ ≥ 0)
2. **Charge + discharge** (allow negative Pᵢₜ, track state of charge)

**Decision Required**:
- [ ] Model batteries as discharge-only generators?
- [ ] Include battery charging (requires state-of-charge tracking)?

---

#### 7.6 Semi-Scheduled Units
**Status**: ❓ **EXCLUDED FROM DATASET**

**Issue**: Clean dataset only has SCHEDULED units (191 units). Semi-scheduled renewable units were filtered out.

**Question**: Should we:
1. **Keep current approach** (optimize only scheduled units, treat semi-scheduled as fixed non-scheduled generation already subtracted)
2. **Include semi-scheduled** (add them back, apply SCADAVALUE caps)

**Decision Required**:
- [ ] Current approach OK (scheduled only)?
- [ ] Include semi-scheduled units?

---

#### 7.7 Regional vs. System-Wide Optimization
**Status**: ❓ **NEEDS CLARIFICATION**

**Question**: Should we:
1. **System-wide**: Single optimization with transmission constraints between regions
2. **Regional**: Separate optimization per region (simpler, ignores inter-regional flows)
3. **Current formulation**: Regional balance with inter-regional flows embedded in residual demand

**Note**: Residual demand already includes `NETINTERCHANGE`, so inter-regional flows are accounted for.

**Decision Required**:
- [ ] Use current regional balance approach?
- [ ] Add explicit transmission constraints?

---

#### 7.8 Reserve Requirements
**Status**: ❌ **NOT INCLUDED**

**Question**: Should we include spinning reserve constraints?

Example:
```
Σᵢ₊ᴵᵣ (Pᵢᵐᵃˣ × uᵢₜ - Pᵢₜ) ≥ Reserveᵣₜ    ∀ r, t
```

Typical reserve: 5-10% of demand

**Decision Required**:
- [ ] Include reserve constraints?
- [ ] Ignore reserves (simplified model)?

---

## 8. Implementation Notes

### Solver Choice

**Recommended**: 
- **Pyomo** with **CBC** or **GLPK** (open-source MILP solvers)
- **PuLP** with **CBC** (simpler API, good for prototyping)
- **Gurobi** or **CPLEX** (commercial, faster for large problems)

**Problem Size Estimate**:
- Continuous variables: 191 units × 48 intervals = **9,168 variables**
- Binary variables: ~130 thermal units × 48 intervals = **~6,240 variables**
- Total variables: **~15,400**
- Constraints: ~50,000-100,000 (depending on min up/down time formulations)

**Solve Time**: 
- Open-source solvers: 1-10 minutes
- Commercial solvers: seconds to 1 minute

---

### Python Implementation Outline

```python
import pyomo.environ as pyo
from pyomo.opt import SolverFactory

# 1. Load data from Delta tables
genset = spark.table("energy_endava_193.default.nsw_generator_initial_state_clean").toPandas()
demand = spark.table("energy_endava_193.default.residual_demand").toPandas()

# 2. Create Pyomo model
model = pyo.ConcreteModel()

# 3. Define sets
model.I = pyo.Set(initialize=genset['DUID'].tolist())
model.T = pyo.RangeSet(1, 48)

# 4. Define parameters (from tables)
model.P0 = pyo.Param(model.I, initialize=...)  # INITIAL_POWER
model.Pmin = pyo.Param(model.I, initialize=...)  # MIN_STABLE_GENERATION
model.Pmax = pyo.Param(model.I, initialize=...)  # MAXCAPACITY
model.R = pyo.Param(model.I, initialize=...)  # MAX_RAMP_RATE_PROXY * 5
model.Cost = pyo.Param(model.I, initialize=...)  # Proxy costs by tech type
model.Demand = pyo.Param(model.R, model.T, initialize=...)  # RESIDUAL_DEMAND

# 5. Define decision variables
model.P = pyo.Var(model.I, model.T, domain=pyo.NonNegativeReals)
model.u = pyo.Var(model.I_thermal, model.T, domain=pyo.Binary)

# 6. Define objective function
def obj_rule(m):
    return sum(m.Cost[i] * m.P[i, t] * (5/60) for i in m.I for t in m.T)
model.obj = pyo.Objective(rule=obj_rule, sense=pyo.minimize)

# 7. Define constraints
# System balance, generation limits, ramping, etc.

# 8. Solve
solver = SolverFactory('cbc')
results = solver.solve(model, tee=True)

# 9. Extract solution
P_solution = {(i, t): pyo.value(model.P[i, t]) for i in model.I for t in model.T}
```

---

### Data Validation Checklist

Before implementation:
- [ ] Verify all 191 units have `MAXCAPACITY`
- [ ] Verify all technology types have constraint data
- [ ] Check for negative or null `INITIAL_POWER` values
- [ ] Ensure `RESIDUAL_DEMAND` is positive (feasibility check)
- [ ] Verify ramp rates are in MW/min (not MW/hour)
- [ ] Confirm time intervals match (48 intervals × 5 min = 240 min = 4 hours)

---

## Next Steps

1. **Resolve Missing Data**: Answer questions in Section 7
2. **Data Validation**: Run validation queries on tables
3. **Cost Assignment**: Define proxy costs by technology type
4. **Implementation**: Write Pyomo/PuLP model in Python
5. **Testing**: Start with small subset (e.g., single region, 12 intervals)
6. **Scaling**: Run full problem (191 units, 48 intervals)
7. **Validation**: Compare solution to actual historical dispatch

---

## References

### Data Tables
- `energy_endava_193.default.nsw_generator_initial_state_clean` (191 units)
- `energy_endava_193.default.nsw_generators_constraints` (14 technology types)
- `energy_endava_193.default.nsw_dictionary_mapped` (789 DUIDs with metadata)
- `energy_endava_193.default.residual_demand` (1440 rows = 288 intervals × 5 regions)
- `energy_endava_193.default.nsw_scada_peak_2022` (SCADA data for renewable caps)

### Documentation
- Initial state red flags: `/Users/quangthanhdong04.au@gmail.com/energy-endava-193/docs/initial_state_red_flags.md`
- Optimization formulation: This document

---

**Document Version**: 1.0  
**Last Updated**: 2026-04-16  
**Author**: Data Engineering Team - Endava Energy Project 193
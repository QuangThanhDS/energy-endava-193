# Optimization Model Mathematical Formulation
**Project**: Energy Endava 193 - Unit Commitment and Economic Dispatch  
**Date**: 2026-04-16  
**Solver**: Pyomo or PuLP (Python)  
**Problem Type**: Mixed Integer Linear Programming (MILP)  
**Status**: Phase 1 - Variable Costs Only (Startup Costs to be added later)

---

## Table of Contents
1. [Problem Overview](#problem-overview)
2. [Sets and Indices](#sets-and-indices)
3. [Decision Variables](#decision-variables)
4. [Parameters](#parameters)
5. [Objective Function](#objective-function)
6. [Constraints](#constraints)
7. [User Decisions Summary](#user-decisions-summary)
8. [Implementation Notes](#implementation-notes)
9. [Pre-Commitment Analysis](#pre-commitment-analysis)

---

## Problem Overview

**Objective**: Minimize the total variable cost of electricity generation while meeting regional demand and respecting physical and operational constraints of generating units.

**Time Horizon**: 2022-11-01 00:05:00 to 2022-11-01 04:00:00 (48 intervals × 5 minutes each)

**Regions**: NSW1, QLD1, SA1, TAS1, VIC1 (National Electricity Market - Australia)

**Units**: 191 scheduled generators with complete constraint data

**Phase 1 Scope**: Variable costs only. Startup costs deferred to Phase 2.

---

## Sets and Indices

### Sets
- $I$ = Set of all scheduled generator units (DUIDs), $|I| = 191$
- $I_{thermal}$ = Subset of thermal/gas units requiring commitment variables
  - STEAM SUB-CRITICAL (46 units)
  - STEAM SUPER CRITICAL (6 units)
  - OPEN CYCLE GAS TURBINES (65 units)
  - COMBINED CYCLE GAS TURBINE (12 units)
  - COMPRESSION RECIPROCATING ENGINE (1 unit)
  - **Total**: ~130 units
- $I_{hydro}$ = Subset of hydro units (36 units: HYDRO-GRAVITY + RUN OF RIVER)
- $I_{renewable}$ = Subset of renewable units (14 battery units)
- $I_{semi}$ = Subset of semi-scheduled units (to be determined from analysis)
- $T$ = Set of time intervals, $t \in \{1, 2, ..., 48\}$ (5-minute intervals)
- $R$ = Set of regions, $r \in \{NSW1, QLD1, SA1, TAS1, VIC1\}$
- $I_r$ = Subset of generators in region $r$

### Indices
- $i$ = Generator unit index
- $t$ = Time interval index
- $r$ = Region index

---

## Decision Variables

### Continuous Variables
$$P_{i,t} \geq 0$$
**Description**: Power output (MW) of generator $i$ at time $t$  
**Dimensions**: $|I| \times |T| = 191 \times 48 = 9,168$ variables  
**Units**: Megawatts (MW)  
**Bounds**: $0 \leq P_{i,t} \leq MaxCapacity_i$

### Binary Variables (Commitment)
$$u_{i,t} \in \{0, 1\}$$
**Description**: Commitment status of unit $i$ at time $t$
- $u_{i,t} = 1$ if unit is ON (committed)
- $u_{i,t} = 0$ if unit is OFF

**Applied to**: Only thermal/gas units in $I_{thermal}$ (~130 units)  
**Dimensions**: $|I_{thermal}| \times |T| \approx 130 \times 48 = 6,240$ binary variables  

**Rationale**: Hydro and battery units can ramp more flexibly and don't require explicit commitment modeling.

---

## Parameters

### Unit-Specific Parameters

| Parameter | Symbol | Description | Data Source | Status |
|-----------|--------|-------------|-------------|--------|
| **Maximum Capacity** | $MaxCapacity_i$ | Maximum power output (MW) | `nsw_dictionary_mapped.MAXCAPACITY` | ✅ Available |
| **Minimum Stable Generation** | $P_{min,i}$ | Minimum power when online (**% of MaxCapacity**) | `nsw_generators_constraints.MIN_STABLE_GENERATION` | ✅ Available |
| **Maximum Ramp Rate** | $RampUp_i$ | Max increase per minute (MW/min) | `nsw_generators_constraints.MAX_RAMP_RATE_PROXY` | ✅ Available (tech-level) |
| **Maximum Ramp Rate** | $RampDown_i$ | Max decrease per minute (MW/min) | `nsw_generators_constraints.MIN_RAMP_RATE_PROXY` | ✅ Available (tech-level) |
| **Startup Time** | $StartupTime_i$ | Time to start from cold (minutes) | `nsw_generators_constraints.STARTUP_TIME` | ✅ Available (tech-level) |
| **Minimum Up Time** | $MinUp_i$ | Min time to stay on (minutes) | `nsw_generators_constraints.MIN_UPTIME` | ✅ Available (tech-level) |
| **Minimum Down Time** | $MinDown_i$ | Min time to stay off (minutes) | `nsw_generators_constraints.MIN_DOWNTIME` | ✅ Available (tech-level) |
| **Initial Power** | $P_{i,0}$ | Power at t=0 (MW) | `nsw_generator_initial_state_clean.INITIAL_POWER` | ✅ Available |
| **Technology Type** | $Tech_i$ | Technology descriptor | `nsw_generator_initial_state_clean.TECHNOLOGYTYPEDESCRIPTOR` | ✅ Available |
| **Region** | $Region_i$ | NEM region | `nsw_generator_initial_state_clean.REGIONID` | ✅ Available |

**✅ CONFIRMED**: MIN_STABLE_GENERATION is in **percentage** of MAXCAPACITY
- Conversion formula: $P_{min,i} = \frac{MIN\_STABLE\_GENERATION_i}{100} \times MaxCapacity_i$ (MW)

### Cost Parameters (✅ **APPROVED BY USER**)

| Parameter | Symbol | Description | Value | Status |
|-----------|--------|-------------|-------|--------|
| **Variable Cost** | $C_{var,i}$ | Cost per MWh by technology | See table below | ✅ **CONFIRMED** |

#### **Approved Proxy Costs by Technology Type**

| Technology Type | Units | Proxy Cost ($/MWh) | Rationale |
|----------------|-------|--------------------|----------|
| **HYDRO - GRAVITY** | 34 | **$0** | No fuel cost, highest priority |
| **RUN OF RIVER** | 6 | **$0** | No fuel cost, highest priority |
| **BATTERY** | 14 | **$5** | Discharge cost (degradation) |
| **PUMP STORAGE** | 2 | **$10** | Energy arbitrage |
| **STEAM SUB-CRITICAL** | 46 | **$40** | Coal-fired, baseload |
| **STEAM SUPER CRITICAL** | 6 | **$45** | High-efficiency coal |
| **COMBINED CYCLE GAS TURBINE** | 12 | **$80** | Gas, mid-merit |
| **OPEN CYCLE GAS TURBINES** | 65 | **$150** | Gas peakers, expensive |
| **COMPRESSION RECIPROCATING ENGINE** | 1 | **$120** | Diesel/gas |
| **AGGREGATED** | 5 | **$100** | Mixed/unknown |

**Purpose**: Merit order dispatch - optimizer selects cheapest units first (hydro → coal → gas)

### System Parameters

| Parameter | Symbol | Description | Data Source | Status |
|-----------|--------|-------------|-------------|--------|
| **Residual Demand** | $Demand_{r,t}$ | Target demand by region & time (MW) | `residual_demand.RESIDUAL_DEMAND` | ✅ Available |
| **Interval Duration** | $\Delta t$ | Time interval length | Fixed: 5 minutes | ✅ Known |
| **SCADA Cap** | $SCADA_{i,t}$ | Renewable output cap (MW) | `nsw_scada_peak_2022.SCADAVALUE` | ✅ Available |

---

## Objective Function

### Minimize Total Variable Cost (Phase 1)

$$
\min Z = \sum_{i \in I} \sum_{t \in T} C_{var,i} \cdot P_{i,t} \cdot \Delta t
$$

**Where**:
- $C_{var,i}$ = Variable cost ($/MWh) for unit $i$ based on technology type (approved values above)
- $P_{i,t}$ = Power output (MW) at time $t$
- $\Delta t$ = Time interval (5 minutes = 1/12 hour)

**Units**: Total cost in dollars ($) for the 4-hour period

**Purpose**: Merit order dispatch - cheaper units (hydro $0, coal $40-45) dispatched before expensive units (gas $80-150)

**Phase 2 Extension** (future):
$$
\min Z = \sum_{i \in I} \sum_{t \in T} C_{var,i} \cdot P_{i,t} \cdot \Delta t + \sum_{i \in I_{thermal}} \sum_{t \in T} C_{startup,i} \cdot SU_{i,t}
$$
where $SU_{i,t} = \max(0, u_{i,t} - u_{i,t-1})$ represents startup events.

---

## Constraints

### 1. System Balance Constraint (✅ **PER-REGION CONFIRMED**)

**Per Region Energy Balance**:
$$
\sum_{i \in I_r} P_{i,t} = Demand_{r,t} \quad \forall r \in R, \forall t \in T
$$

**Where**: 
- $I_r$ = Set of generators in region $r$
- $Demand_{r,t}$ = Residual demand in region $r$ at time $t$ (MW)

**Constraint Count**: 48 time periods × 5 regions = **240 constraints**  
**Type**: Equality constraint  
**Purpose**: Each region must independently meet its own demand (no inter-regional flows modeled)

**Note**: This formulation assumes no interconnector constraints. Each region balances locally.

---

### 2. Unit Capacity Limits

#### 2a. Maximum Capacity
$$
P_{i,t} \leq MaxCapacity_i \cdot u_{i,t} \quad \forall i \in I_{thermal}, \forall t \in T
$$

**For non-thermal units** (hydro, battery) without commitment variables:
$$
P_{i,t} \leq MaxCapacity_i \quad \forall i \in (I \setminus I_{thermal}), \forall t \in T
$$

**Constraint Count**: $191 \times 48 = 9,168$ constraints  
**Type**: Inequality constraint  
**Purpose**: Unit cannot generate beyond rated capacity (or cannot generate when off)

#### 2b. Minimum Stable Generation
$$
P_{i,t} \geq \frac{MIN\_STABLE\_GENERATION_i}{100} \times MaxCapacity_i \cdot u_{i,t} \quad \forall i \in I_{thermal}, \forall t \in T
$$

**✅ CONFIRMED**: MIN_STABLE_GENERATION values (102, 75, 60, etc.) are **percentages**

**Example**: 
- Steam Sub-Critical: MIN_STABLE_GENERATION = 40%
- If MaxCapacity = 500 MW, then $P_{min} = 0.40 \times 500 = 200$ MW
- When unit is ON ($u_{i,t}=1$), must generate at least 200 MW

**Constraint Count**: $130 \times 48 = 6,240$ constraints  
**Type**: Inequality constraint  
**Purpose**: Thermal units must operate above minimum stable level when online

---

### 3. Ramping Constraints

#### 3a. Ramp-Up Limit
$$
P_{i,t} - P_{i,t-1} \leq RampUp_i \cdot \Delta t \quad \forall i \in I, \forall t \in T \setminus \{1\}
$$

**For first interval** (using initial state):
$$
P_{i,1} - P_{i,0} \leq RampUp_i \cdot \Delta t \quad \forall i \in I
$$

**Where**:
- $RampUp_i$ = `MAX_RAMP_RATE_PROXY` (MW/min) from constraints table
- $\Delta t$ = 5 minutes
- $P_{i,0}$ = `INITIAL_POWER` from initial state table

**Constraint Count**: $191 \times 48 = 9,168$ constraints  
**Type**: Inequality constraint

#### 3b. Ramp-Down Limit
$$
P_{i,t-1} - P_{i,t} \leq RampDown_i \cdot \Delta t \quad \forall i \in I, \forall t \in T \setminus \{1\}
$$

**For first interval**:
$$
P_{i,0} - P_{i,1} \leq RampDown_i \cdot \Delta t \quad \forall i \in I
$$

**Where**:
- $RampDown_i$ = `MIN_RAMP_RATE_PROXY` (MW/min) from constraints table
- Note: This represents maximum ramp-DOWN rate (positive value)

**Constraint Count**: $191 \times 48 = 9,168$ constraints  
**Type**: Inequality constraint

**Note**: Current data has same value for MIN and MAX ramp rate proxy (symmetric ramping).

---

### 4. Renewable Capacity Constraint (Semi-Scheduled Units)

$$
P_{i,t} \leq SCADA_{i,t} \quad \forall i \in I_{semi}, \forall t \in T
$$

**Where**:
- $SCADA_{i,t}$ = `SCADAVALUE` from `nsw_scada_peak_2022` table
- Represents actual or forecasted renewable output cap

**⚠️ TO BE DETERMINED**: Which units are "semi-scheduled"?
- Analysis needed to evaluate options (battery units vs. specific schedule types)
- See Section 9 for evaluation

**Constraint Count**: Depends on $|I_{semi}|$ × 48  
**Type**: Inequality constraint  
**Purpose**: Renewable units cannot exceed available resource (wind/solar/battery SOC)

---

### 5. Minimum Up Time Constraint

$$
\sum_{\tau=t-MinUp_i+1}^{t} SU_{i,\tau} \leq u_{i,t} \quad \forall i \in I_{thermal}, \forall t \in T
$$

**Where**: $SU_{i,t} = u_{i,t} - u_{i,t-1}$ (startup indicator)

**Interpretation**: If unit started up in the last $MinUp_i$ minutes, it must remain on.

**Constraint Count**: $130 \times 48 = 6,240$ constraints  
**Type**: Inequality constraint

---

### 6. Minimum Down Time Constraint

$$
\sum_{\tau=t-MinDown_i+1}^{t} SD_{i,\tau} \leq 1 - u_{i,t} \quad \forall i \in I_{thermal}, \forall t \in T
$$

**Where**: $SD_{i,t} = u_{i,t-1} - u_{i,t}$ (shutdown indicator)

**Interpretation**: If unit shut down in the last $MinDown_i$ minutes, it must remain off.

**Constraint Count**: $130 \times 48 = 6,240$ constraints  
**Type**: Inequality constraint

---

### 7. Initial State Constraints

#### 7a. Initial Commitment State (for thermal units)
$$
u_{i,0} = 
\begin{cases}
1 & \text{if } P_{i,0} > 0 \\
0 & \text{if } P_{i,0} = 0
\end{cases}
\quad \forall i \in I_{thermal}
$$

**Purpose**: Anchor commitment variable to historical initial state.

#### 7b. Initial Power State
$$
P_{i,0} = INITIAL\_POWER_i \quad \forall i \in I
$$

**Data Source**: `nsw_generator_initial_state_clean.INITIAL_POWER`  
**Purpose**: Provides anchor for first-interval ramping constraints.

---

### 8. Pre-Commitment Constraints (✅ **COLD START POLICY**)

**Decision**: Units starting from zero ($P_{i,0} = 0$) should be **pre-committed based on expected need**.

**Implementation**:
For units identified as "must-commit" (based on regional demand and startup time analysis):
$$
u_{i,t} = 1 \quad \forall i \in I_{precommit}, \forall t \geq \frac{StartupTime_i}{\Delta t}
$$

**Where**:
- $I_{precommit}$ = Set of units pre-committed to start (to be determined from analysis)
- Unit can only generate after its startup time has elapsed

**Analysis Required** (see Section 9):
1. Identify which of the 159 cold-start units need to be committed
2. Consider startup times (17-75 minutes)
3. Match to regional demand requirements
4. Ensure feasibility (can't start all units immediately)

---

## User Decisions Summary

### ✅ Decisions Made

| Question | Decision | Implementation |
|----------|----------|----------------|
| **1. Variable Costs** | Use proposed values | Costs range from $0 (hydro) to $150 (OCGT) per MWh |
| **2. MIN_STABLE_GENERATION** | Percentage of MAXCAPACITY | Convert to MW: $P_{min,i} = \frac{MIN\_STABLE\_GENERATION}{100} \times MaxCapacity_i$ |
| **3. System Balance** | Per-region | Each region balances independently: $\sum_{i \in I_r} P_{i,t} = Demand_{r,t}$ |
| **5. Startup Costs** | Phase 1: Variable costs only | Simplify objective, add startup costs in Phase 2 |
| **6. Cold Start Policy** | Pre-commit based on need | Identify must-commit units and apply $u_{i,t}=1$ constraints |

### ⚠️ Decisions Pending Analysis

| Question | Status | Action Required |
|----------|--------|----------------|
| **4. Semi-Scheduled Units** | Evaluate options | Run analysis: Battery units vs. SCHEDULE_TYPE filter |
| **Pre-Commitment Set** | Identify candidates | Analyze 159 cold-start units, startup times, regional demand |

---

## Implementation Notes

### Solver Selection

**Recommended**: **Pyomo** with **CBC** (free) or **Gurobi** (commercial, faster)

**Rationale**:
- Pyomo: More expressive, better for complex constraints
- PuLP: Simpler API, good for smaller problems
- Problem size: ~9,000 continuous + ~6,000 binary variables = MILP, solvable in seconds to minutes

### Model Structure
```python
from pyomo.environ import *

# Create model
model = ConcreteModel(name="Unit_Commitment_ED")

# Sets
model.I = Set(initialize=unit_list)  # All units
model.I_thermal = Set(initialize=thermal_units)  # Thermal units only
model.T = RangeSet(1, 48)  # Time periods
model.R = Set(initialize=['NSW1', 'QLD1', 'SA1', 'TAS1', 'VIC1'])  # Regions

# Decision variables
model.P = Var(model.I, model.T, domain=NonNegativeReals, bounds=lambda m,i,t: (0, MaxCap[i]))
model.u = Var(model.I_thermal, model.T, domain=Binary)

# Parameters
model.C_var = Param(model.I, initialize=cost_dict)  # Variable costs
model.P_min_pct = Param(model.I, initialize=min_gen_pct)  # Min gen %
model.MaxCap = Param(model.I, initialize=max_cap_dict)  # Max capacity
model.RampUp = Param(model.I, initialize=ramp_up_dict)  # Ramp rates
model.Demand = Param(model.R, model.T, initialize=demand_dict)  # Regional demand

# Objective
def obj_rule(m):
    return sum(m.C_var[i] * m.P[i,t] * 5/60 for i in m.I for t in m.T)  # 5 min = 1/12 hr
model.obj = Objective(rule=obj_rule, sense=minimize)

# Constraints
def balance_rule(m, r, t):
    return sum(m.P[i,t] for i in units_in_region[r]) == m.Demand[r,t]
model.balance = Constraint(model.R, model.T, rule=balance_rule)

def min_gen_rule(m, i, t):
    if i in thermal_units:
        return m.P[i,t] >= (m.P_min_pct[i]/100) * m.MaxCap[i] * m.u[i,t]
    else:
        return Constraint.Skip
model.min_gen = Constraint(model.I, model.T, rule=min_gen_rule)

# ... (other constraints)
```

### Data Preparation Steps

1. ✅ **Load clean initial state**: `nsw_generator_initial_state_clean`
2. ✅ **Load constraints**: `nsw_generators_constraints` 
3. ✅ **Join on technology type** to map constraints to each unit
4. ✅ **Load residual demand**: `residual_demand`
5. ✅ **Assign costs**: Create mapping from technology type → approved cost
6. ✅ **Define thermal set**: Filter units where tech type in [STEAM, GAS, OCGT, CCGT]
7. ⚠️ **Load SCADA data**: For renewable cap constraints (pending analysis)
8. ⚠️ **Identify pre-commit set**: Analyze cold-start units (pending analysis)

### Verification Tests

- [ ] Check for infeasibility: Can total capacity meet peak demand?
- [ ] Validate ramping: Are ramp constraints reasonable for 5-min intervals?
- [ ] Test initial state: Do initial ramping constraints allow feasible solutions?
- [ ] Verify costs: Does merit order make sense (hydro before coal before gas)?
- [ ] Check commitment logic: Do binary variables behave correctly?
- [ ] Validate MIN_STABLE_GENERATION: Converted percentages to MW correctly?
- [ ] Test per-region balance: Each region meets its own demand?

---

## Pre-Commitment Analysis

### Cold Start Units Requiring Analysis

**Context**: 159 units start from zero power ($P_{i,0} = 0$)

**Startup Times by Technology** (from constraints table):

| Technology Type | Startup Time (min) | Units at Zero |
|----------------|-------------------|---------------|
| STEAM SUB-CRITICAL | 60 | TBD |
| STEAM SUPER CRITICAL | 75 | TBD |
| COMBINED CYCLE GAS TURBINE | 55 | TBD |
| OPEN CYCLE GAS TURBINES | 17 | TBD |
| HYDRO - GRAVITY | 5 | TBD |
| BATTERY | 0 | TBD |
| RUN OF RIVER | 0 | TBD |
| PUMP STORAGE | 25 | TBD |
| COMPRESSION RECIPROCATING ENGINE | 20 | TBD |
| AGGREGATED | 0 | TBD |

**Analysis Approach**:

1. **Regional Capacity Check**:
   - Compare total available capacity (units ON at t=0) vs. peak regional demand
   - Identify regions with capacity shortfall requiring cold starts

2. **Startup Feasibility**:
   - Units with 60-75 min startup can only contribute in later intervals (t > 12-15)
   - Fast-start units (OCGT 17 min, Hydro 5 min) can ramp within optimization horizon

3. **Pre-Commitment Strategy**:
   - **Must-commit**: Base load units needed to meet minimum demand (coal)
   - **Fast reserves**: OCGT and hydro for peak periods
   - **Exclude**: Units with startup time > 240 min (beyond 4-hour horizon)

4. **Minimum Commitment by Region**:
   - Calculate: $Capacity\_Gap_r = \max_t(Demand_{r,t}) - \sum_{i \in I_r, P_{i,0}>0} MaxCapacity_i$
   - If $Capacity\_Gap_r > 0$, must commit additional units

**Implementation Cells Required**:
- Cell A: Calculate regional capacity gaps
- Cell B: Identify cold-start units by technology and startup time
- Cell C: Recommend pre-commitment set based on gap and startup feasibility
- Cell D: Create pre-commitment parameter table

---

## Next Steps

### Immediate Actions (Analysis Required)

1. ⚠️ **Evaluate semi-scheduled options**:
   - Option A: All battery units (14 units)
   - Option B: Filter by `SCHEDULE_TYPE = 'SEMI-SCHEDULED'` from original data
   - Option C: None (conservative approach)
   - **Action**: Create analysis cell to compare options

2. ⚠️ **Pre-commitment analysis**:
   - Analyze 159 cold-start units
   - Calculate regional capacity gaps
   - Identify must-commit units considering startup times
   - **Action**: Create analysis cells (see Section 9)

### Development Actions (After Analysis)

1. Create parameter mapping tables:
   - Technology → Variable costs (approved values)
   - Technology → MIN_STABLE_GENERATION (convert % to MW)
   - DUID → Region assignment
   - Pre-commitment set (from analysis)

2. Implement Pyomo model structure:
   - Decision variables (P, u)
   - Objective function (variable costs only)
   - Constraint sets (1-8)

3. Write data preprocessing functions:
   - Load and join data tables
   - Convert percentages to MW
   - Filter by region

4. Develop unit tests for constraint logic:
   - Test ramping constraints
   - Test min/max capacity
   - Test per-region balance

5. Run small-scale test:
   - Single region (NSW1)
   - 6 intervals (30 minutes)
   - Verify feasibility and costs

6. Scale to full problem:
   - All 5 regions
   - 48 intervals (4 hours)
   - Analyze solve time

7. Visualize results:
   - Generation by technology over time
   - Regional supply/demand balance
   - Merit order dispatch verification
   - Commitment status (on/off)

---

## References

### Data Tables
- `energy_endava_193.default.nsw_generator_initial_state_clean` - Clean initial state (191 units)
- `energy_endava_193.default.nsw_generators_constraints` - Technology-level constraints
- `energy_endava_193.default.nsw_dictionary_mapped` - Unit metadata
- `energy_endava_193.default.residual_demand` - Target demand by region/time
- `energy_endava_193.default.nsw_scada_peak_2022` - SCADA values for cap constraints

### Documentation
- `/Users/quangthanhdong04.au@gmail.com/energy-endava-193/docs/initial_state_red_flags.md` - Data quality analysis
- Current file: Mathematical formulation with approved parameters

### Solver Documentation
- [Pyomo Documentation](https://pyomo.readthedocs.io/)
- [PuLP Documentation](https://coin-or.github.io/pulp/)
- [CBC Solver](https://github.com/coin-or/Cbc)

---

## Changelog

**2026-04-16 - Initial Version**
- Complete mathematical formulation
- Identified missing data and open questions

**2026-04-16 - User Decisions Incorporated**
- ✅ Approved variable costs ($0-$150 per MWh)
- ✅ Confirmed MIN_STABLE_GENERATION as percentage
- ✅ Set per-region energy balance
- ✅ Phase 1: Variable costs only (no startup costs)
- ✅ Cold start policy: Pre-commit based on need
- ⚠️ Pending: Semi-scheduled unit definition
- ⚠️ Pending: Pre-commitment set identification
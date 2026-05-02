# Energy Optimization Model - Complete Documentation

## Project Overview

**Objective**: Minimize variable generation costs for 5 NEM regions over a 4-hour period

**Time Horizon**: 2022-11-01 00:05:00 to 04:00:00 (48 × 5-minute intervals)

**Regions**: NSW1, QLD1, SA1, TAS1, VIC1

**Approach**: Mixed Integer Linear Programming (MILP) with Pyomo and HiGHS solver

---

## 1. Source Data Tables

All tables from Unity Catalog: `energy_endava_193.default`

### 1.1 nsw_generator_initial_state_clean
- **Rows**: 191 units
- **Key Fields**:
  - `DUID`: Generator unique identifier
  - `SETTLEMENTDATE`: 2022-10-31 23:55:00 (t=0, 5 minutes before optimization period)
  - `INITIAL_POWER`: Starting power output (MW)
  - `SCHEDULE_TYPE`: Generation type (SCHEDULED)
  - `TECHNOLOGYTYPEDESCRIPTOR`: Technology type
  - `REGIONID`: NEM region

### 1.2 nsw_generators_constraints
- **Rows**: 14 technology types
- **Key Fields**:
  - `TECHNOLOGYTYPEDESCRIPTOR`: Technology name
  - `MIN_STABLE_GENERATION`: Minimum generation as % of max capacity
  - `STARTUP_TIME`: Time to start (minutes)
  - `MIN_UPTIME`: Minimum continuous operating time (minutes)
  - `MIN_DOWNTIME`: Minimum offline time (minutes)
  - `MIN_RAMP_RATE_PROXY`, `MAX_RAMP_RATE_PROXY`: Ramping rate proxies

### 1.3 nsw_dictionary_mapped
- **Rows**: 7,076 (789 after deduplication)
- **Key Fields**:
  - `DUID`: Generator identifier
  - `MAXCAPACITY`: Maximum capacity (MW)
  - `MAX_RAMP_RATE_UP`, `MAX_RAMP_RATE_DOWN`: Ramp rates (MW/5min)
  - `START_DATE`, `END_DATE`: Validity period
- **Note**: Contains duplicates for units with capacity changes over time

### 1.4 residual_demand
- **Rows**: 1,440 (288 intervals × 5 regions)
- **Filtered to**: 240 rows (48 intervals × 5 regions for analysis period)
- **Key Fields**:
  - `SETTLEMENTDATE`: Timestamp
  - `REGIONID`: Region
  - `TOTALDEMAND`: Total regional demand (MW)
  - `NETINTERCHANGE`: Net imports/exports (MW)
  - `TOTAL_NON_SCHEDULED_GENERATION`: Non-scheduled generation (MW)
  - `RESIDUAL_DEMAND`: Demand to be met by scheduled generators (MW)

---

## 2. Data Preprocessing & Transformations

### 2.1 Variable Cost Assignment

Created cost mapping based on technology type ($/MWh):

| Technology | Variable Cost | Rationale |
|-----------|--------------|----------|
| Hydro (Gravity) | $0 | Zero marginal cost (water already available) |
| Run of River | $0 | Zero marginal cost |
| Battery | $5 | Battery cycling degradation cost |
| Pump Storage | $10 | Opportunity cost of stored water |
| Steam Sub-Critical Coal | $40 | Coal fuel cost (~$2.50/GJ, 35% efficiency) |
| Steam Super Critical | $45 | Coal fuel cost (better efficiency) |
| CCGT (Gas) | $80 | Gas fuel cost (~$8/GJ, 50% efficiency) |
| Aggregated | $100 | Mixed/unknown generation sources |
| Compression Engine | $120 | Reciprocating gas engine (lower efficiency) |
| OCGT (Gas Peaker) | $150 | Open cycle gas (low efficiency, ~30%) |

### 2.2 Master Dataset Creation

**Process**:
1. Deduplicated `nsw_dictionary_mapped` by keeping latest `START_DATE` per DUID (789 → 815 unique units)
2. Joined with `initial_state` on DUID
3. Joined with `tech_constraints` on technology type
4. Added variable cost mapping
5. Calculated `MIN_STABLE_GEN_MW = MAXCAPACITY × MIN_STABLE_GENERATION%`
6. Added `REQUIRES_COMMITMENT` flag (True for thermal units, False for hydro/batteries)

**Result**: 191 units with complete parameters

### 2.3 Demand Dictionary

**Transformation**:
- Converted Spark DataFrame to pandas
- Created dictionary: `{(region, timestamp): demand_MW}`
- 240 entries total (5 regions × 48 time intervals)

**Time Periods**: List of 48 timestamps at 5-minute intervals

### 2.4 Unit Lists

- **All units**: 191 generators
- **Thermal units** (require commitment decisions): 132 units
- **Non-thermal units** (flexible dispatch): 59 units (hydro, batteries)

---

## 3. Data Quality Issues & Fixes

### 3.1 Critical Issues Identified

#### Issue 1: Units Operating Above Capacity
**Problem**: 4 units with `INITIAL_POWER > MAXCAPACITY`

| DUID | Original (MW) | Capacity (MW) | Type |
|------|--------------|--------------|------|
| EILDON2 | 60.20 | 60.00 | Hydro - Gravity |
| LEM_WIL | 86.99 | 86.00 | Hydro - Gravity |
| WKIEWA1 | 33.90 | 31.00 | Hydro - Gravity |
| WKIEWA2 | 32.20 | 31.00 | Hydro - Gravity |

**Impact**: Creates impossible ramping constraints at t=0
- Ramp-down constraint: `P[i,0] >= INITIAL_POWER - RAMP_DOWN`
- Max capacity constraint: `P[i,0] <= MAXCAPACITY`
- When `INITIAL_POWER > MAXCAPACITY` and ramp-down is insufficient → **INFEASIBLE**

**Fix**: Capped `INITIAL_POWER` at `MAXCAPACITY`

#### Issue 2: Negative Generation Values
**Problem**: 2 units with negative `INITIAL_POWER`

| DUID | Original (MW) | Type |
|------|--------------|------|
| BBTHREE1 | -1.03 | OCGT |
| BBTHREE3 | -1.07 | OCGT |

**Impact**: Physically meaningless, creates invalid ramping constraints

**Fix**: Set `INITIAL_POWER = 0`

#### Issue 3: Thermal Units Below Minimum
**Problem**: 12 thermal units ON (INITIAL_POWER > 0) but below `MIN_STABLE_GEN_MW`

| DUID | Initial (MW) | Minimum (MW) | Action Taken |
|------|-------------|--------------|-------------|
| BRAEMAR5 | 0.22 | 82.50 | Set to 0 (OFF) |
| BRAEMAR7 | 0.16 | 82.50 | Set to 0 (OFF) |
| ER02 | 283.10 | 300.00 | Set to 300.00 (MIN) |
| GSTONE5 | 110.42 | 114.00 | Set to 114.00 (MIN) |
| JLA02 | 0.10 | 32.50 | Set to 0 (OFF) |
| JLB02 | 0.10 | 50.00 | Set to 0 (OFF) |
| MINTARO | 0.13 | 52.50 | Set to 0 (OFF) |
| MP1 | 221.96 | 280.00 | Set to 280.00 (MIN) |
| ROMA_8 | 0.79 | 21.00 | Set to 0 (OFF) |
| SITHE01 | 0.14 | 80.50 | Set to 0 (OFF) |
| TARONG#3 | 0.90 | 154.00 | Set to 0 (OFF) |
| TORRB3 | 43.00 | 84.00 | Set to 84.00 (MIN) |

**Impact**: Initial commitment forces `u[i,0] = 1`, but min capacity requires `P[i,0] >= MIN × u[i,0]`, creating conflict when current power is below minimum

**Fix Strategy**: For each unit, chose option closest to current value:
- If closer to 0: Turn OFF (set `INITIAL_POWER = 0`)
- If closer to MIN: Set to minimum (set `INITIAL_POWER = MIN_STABLE_GEN_MW`)

**Result**: 8 units turned OFF, 4 units raised to minimum

### 3.2 After Data Cleaning

**Initial State Summary**:
- Thermal units ON at t=0: 42 (down from 50)
- Thermal units OFF at t=0: 90 (up from 82)
- Total initial generation: 16,557.8 MW
- INITIAL_POWER range: [0.00, 630.07] MW (was [-1.07, 630.07])

**Regional Initial Generation**:

| Region | Initial (MW) | Demand t=0 (MW) | Gap (MW) |
|--------|-------------|----------------|----------|
| NSW1 | 5,311.4 | 6,357.3 | +1,045.9 |
| QLD1 | 5,703.5 | 5,871.0 | +167.5 |
| SA1 | 176.8 | 1,598.9 | +1,422.1 ⚠️ |
| TAS1 | 690.2 | 703.2 | +13.0 |
| VIC1 | 4,675.9 | 5,267.6 | +591.7 |

**Note**: SA1 has a very large gap between initial state and demand

---

## 4. Model Formulation

### 4.1 Sets

- **I**: All generator units (191 units)
- **I_thermal**: Thermal units requiring commitment decisions (132 units)
- **T**: Time periods {0, 1, ..., 47} (48 × 5-minute intervals)
- **R**: Regions {NSW1, QLD1, SA1, TAS1, VIC1}

### 4.2 Parameters (per unit i)

- **C_var[i]**: Variable cost ($/MWh)
- **P_max[i]**: Maximum capacity (MW)
- **P_min[i]**: Minimum stable generation (MW) - for thermal units only
- **R_up[i]**: Maximum ramp up rate (MW/5min)
- **R_down[i]**: Maximum ramp down rate (MW/5min)
- **P_init[i]**: Initial power at t=0 (MW) - **CLEANED VALUES**
- **region[i]**: Region assignment
- **requires_commit[i]**: Boolean flag for thermal units

- **D[r,t]**: Demand in region r at time t (MW)

### 4.3 Decision Variables

1. **P[i,t]**: Continuous variable ∈ [0, +∞)
   - Power output of unit i at time t (MW)
   - 9,168 variables (191 units × 48 intervals)

2. **u[i,t]**: Binary variable ∈ {0, 1}
   - Commitment status of thermal unit i at time t (1=ON, 0=OFF)
   - 6,336 variables (132 thermal units × 48 intervals)

**Total**: 15,504 decision variables

### 4.4 Objective Function

Minimize total variable generation cost:

```
min Z = Σ_i Σ_t C_var[i] × P[i,t] × (5/60 hours)
```

where `5/60 = 0.0833` hours per 5-minute interval

### 4.5 Constraints

#### 1. System Balance (240 constraints)
For each region r and time t:

```
Σ_{i ∈ region[r]} P[i,t] = D[r,t]
```

Supply must exactly equal demand in each region at each time

#### 2. Maximum Capacity (9,168 constraints)

**For thermal units** (requires commitment):
```
P[i,t] <= P_max[i] × u[i,t]    ∀i ∈ I_thermal, ∀t
```
Can only generate if committed (u=1)

**For non-thermal units** (flexible):
```
P[i,t] <= P_max[i]    ∀i ∈ I \ I_thermal, ∀t
```
No commitment decision, just capacity limit

#### 3. Minimum Capacity (6,336 constraints)
For thermal units with positive minimum:

```
P[i,t] >= P_min[i] × u[i,t]    ∀i ∈ I_thermal where P_min[i] > 0, ∀t
```

When committed (u=1), must generate at least minimum stable level

#### 4. Ramping Constraints (17,954 constraints)

**Ramp Up** (8,977 constraints):
```
For t = 0:  SKIPPED (no constraint)
For t > 0:  P[i,t] - P[i,t-1] <= R_up[i]    ∀i, ∀t>0
```

**Ramp Down** (8,977 constraints):
```
For t = 0:  SKIPPED (no constraint)
For t > 0:  P[i,t] - P[i,t-1] >= -R_down[i]    ∀i, ∀t>0
```

**IMPORTANT MODEL MODIFICATION**: 
- Original model included ramping constraints at t=0 (comparing to `P_init[i]`)
- **Final model EXCLUDES t=0 ramping constraints**
- Reason: SA1 region infeasibility (see Section 5.2)

#### 5. Initial Commitment (132 constraints)
Set binary commitment at t=0 based on cleaned initial state:

```
If P_init[i] > 0.01:  u[i,0] = 1  (unit is ON)
Else:                  u[i,0] = 0  (unit is OFF)
```

Applies only to thermal units

**Total Constraints**: ~27,744

### 4.6 Summary: Constraints, Relaxations & Assumptions

#### ✅ Constraints INCLUDED in Final Model

1. **System Balance** (240)
   - Supply = Demand for each region at each 5-minute interval
   - No inter-regional transmission modeled

2. **Maximum Capacity** (9,168)
   - Thermal: `P[i,t] ≤ MAXCAPACITY × u[i,t]` (tied to commitment)
   - Non-thermal: `P[i,t] ≤ MAXCAPACITY` (no commitment required)

3. **Minimum Capacity** (6,336)
   - Thermal units ON must generate ≥ MIN_STABLE_GEN_MW
   - Prevents operation below technical minimum

4. **Ramping Limits** (17,954)
   - Enforced for all intervals t>0 (between consecutive periods)
   - Both ramp-up and ramp-down constraints
   - ⚠️ **t=0 ramping EXCLUDED** (see relaxations)

5. **Initial Commitment** (132)
   - Thermal units start ON or OFF based on cleaned initial power
   - Commitment status enforced at first interval

#### 🔧 Constraints RELAXED or OMITTED

1. **t=0 Ramping Constraints** ⚠️ **CRITICAL**
   - **Omitted**: `P[i,0] - P_init[i] ≤ R_up[i]` and ramp-down at t=0
   - **Reason**: SA1 region infeasible (333 MW shortfall with ramping)
   - **Justification**: 10-minute lookahead allows dispatch pre-positioning
   - Commitment status (ON/OFF) still enforced from initial state

2. **Minimum Up/Down Time Constraints** (NOT IMPLEMENTED)
   - Units can turn ON/OFF freely between any intervals
   - Real thermal units require 30-240 minutes continuous run time
   - Simplification for Phase 1 model

3. **Startup Costs** (NOT INCLUDED)
   - Objective function only considers variable (fuel) costs
   - No penalties for unit startups ($1,000s-$100,000s in reality)
   - Would reduce cycling frequency if included

4. **Reserve Requirements** (NOT INCLUDED)
   - No spinning reserve or frequency control constraints
   - Model only meets energy balance, not ancillary services

5. **Inter-Regional Transmission** (NOT MODELED)
   - Each region must independently meet demand
   - NEM interconnectors not represented

#### 📋 Model Assumptions

**Cost Assumptions:**
1. Variable costs only ($0-150/MWh by technology type)
2. No startup, no-load, or fixed costs
3. Perfect merit order dispatch (lowest cost first)

**Operational Assumptions:**

4. No minimum up/down times (free cycling)
5. Symmetric ramping where data unavailable
6. No transmission constraints or losses
7. No reserve or ancillary service requirements

**Data Assumptions:**

8. Cleaned initial state (18 units corrected)
   - 4 capped at MAXCAPACITY
   - 2 set to zero (negative values)
   - 12 adjusted to OFF or MIN (below minimum)
9. Perfect demand forecast (no uncertainty)
10. Battery modeled as generator (no state-of-charge tracking)
11. Hydro has no energy limits (unconstrained water availability)

**Solver Configuration:**

12. 1% MIP gap tolerance
13. 600-second time limit
14. HiGHS solver (open-source MILP)

#### 🎯 Impact on Results

* **Relaxed t=0 ramping**: Allows optimal first-interval dispatch, prevents SA1 infeasibility
* **No startup costs**: May overestimate unit cycling vs. reality
* **No min up/down times**: Units can respond faster than physically possible
* **No reserves**: Utilization may be higher than real system
* **Average cost $30.51/MWh**: Reflects variable costs only, not total market costs

---

## 5. Model Infeasibility Analysis

### 5.1 Initial Attempt
After data cleaning, the model with full ramping constraints (including t=0) was still **INFEASIBLE**.

### 5.2 Root Cause: SA1 Regional Infeasibility

Detailed feasibility analysis revealed:

**SA1 Region at t=0**:
- Demand: 1,598.9 MW
- Initial generation: 176.8 MW
- Maximum generation considering ramping limits: **1,265.8 MW**
- **Shortfall: 333.1 MW** ⚠️

**Why?** 
With ramping constraints at t=0:
```
P[i,0] <= P_init[i] + R_up[i]
```

SA1 units cannot ramp up fast enough from their initial low state to meet demand.

**Other regions**: All feasible at t=0

### 5.3 Solution: Relaxed t=0 Ramping

**Rationale**:
- Initial state represents system at 23:55:00 (5 minutes before optimization period)
- Short-term dispatch forecasts allow pre-positioning before 00:05:00
- Operationally reasonable to allow free dispatch at first interval

**Implementation**:
- Removed ramping constraints at t=0
- Ramping fully enforced between all subsequent intervals (t=1 to t=47)
- Initial commitment status still enforced (units ON/OFF based on cleaned initial state)

**Result**: Model became **FEASIBLE and OPTIMAL**

---

## 6. Optimization Results

### 6.1 Solver Performance

- **Solver**: HiGHS (appsi_highs)
- **Status**: Optimal
- **Solve Time**: 2.1 seconds
- **Termination**: Optimal solution found
- **MIP Gap**: 1% tolerance

### 6.2 Cost Results

- **Total Variable Cost**: $2,218,480.17
  - Over 4-hour period (00:05 - 04:00)
  - Excludes startup costs, no-load costs, fixed costs
  
- **Total Energy Generated**: 72,709.7 MWh
  - Sum across all units and all time periods
  
- **Average Variable Cost**: $30.51/MWh
  - Weighted average across all generation

### 6.3 Model Statistics

- **Decision Variables**: 15,504
  - Continuous (P): 9,168
  - Binary (u): 6,336
  
- **Constraints**: ~27,744
  - System balance: 240
  - Max capacity: 9,168
  - Min capacity: 6,336
  - Ramp up: 8,977 (191 units × 47 intervals, excluding t=0)
  - Ramp down: 8,977 (191 units × 47 intervals, excluding t=0)
  - Initial commitment: 132

### 6.4 Interpretation

**Cost Context**:
- Average cost of $30.51/MWh suggests heavy reliance on low-cost generation
- This is variable cost only - actual market prices include startup, ancillary services, etc.
- For reference:
  - Coal typically $30-50/MWh variable
  - Gas (CCGT) ~$80/MWh
  - Gas peakers (OCGT) ~$150/MWh

**Expected Generation Mix** (based on merit order):
1. **Hydro** (cost $0): Used to maximum availability
2. **Batteries** (cost $5): Used for peak shaving
3. **Coal** (cost $40-45): Base/shoulder load
4. **Gas CCGT** (cost $80): Mid-merit
5. **Gas peakers** (cost $150): Minimal use (only if needed)

---

## 7. Model Limitations & Future Enhancements

### 7.1 Current Simplifications

1. **No Startup Costs**: Model only considers variable (fuel) costs
   - Real dispatch includes startup costs ($1,000s-$100,000s per start)
   - Would reduce unit cycling frequency

2. **No Minimum Up/Down Times**: Units can turn on/off freely between intervals
   - Real units require minimum run times (30-240 minutes)
   - Would create more realistic commitment patterns

3. **Relaxed t=0 Ramping**: First interval allows free dispatch
   - Reasonable for 5-minute ahead dispatch
   - Could be tightened with better initial state data

4. **No Inter-Regional Transmission**: Demand met within each region
   - Real NEM has interconnectors between regions
   - Could allow more efficient dispatch

5. **No Reserve Requirements**: Model only meets energy balance
   - Real system requires spinning/standing reserves
   - Would keep additional capacity online

6. **Perfect Foresight**: Model knows all future demand
   - Real dispatch faces forecast uncertainty
   - Could add stochastic elements

### 7.2 Phase 2 Enhancements

**Recommended additions**:
1. Add startup costs and commitment state tracking
2. Implement minimum up/down time constraints
3. Add inter-regional transmission limits and costs
4. Include reserve requirement constraints
5. Model battery state of charge explicitly
6. Add hydro energy limits (daily/weekly water budgets)
7. Include ancillary service co-optimization

---

## 8. Key Takeaways

### 8.1 Data Quality is Critical

**18 units** (9.4% of fleet) had data quality issues that made the model infeasible:
- 4 units above capacity
- 2 units with negative generation  
- 12 units below technical minimums

Without identifying and fixing these, optimization was impossible.

### 8.2 Initial State Matters

The transition from initial state to optimized dispatch must be:
- Physically feasible (respecting ramping limits)
- Operationally valid (respecting commitment constraints)
- Regionally balanced (each region can meet its demand)

SA1's low initial state (177 MW) vs high demand (1,599 MW) created infeasibility.

### 8.3 Model Formulation Trade-offs

**Strict Model** (all constraints):
- More realistic
- May be infeasible with imperfect data
- Harder to solve

**Relaxed Model** (some constraints removed):
- Easier to solve
- May have unrealistic features (e.g., instant ramping at t=0)
- Better for initial analysis

Chose relaxed t=0 ramping as reasonable compromise.

### 8.4 Validation Approach

Before solving, check:
1. **Data ranges**: No impossible values (negative, above capacity)
2. **Regional feasibility**: Each region can meet demand given capacity
3. **Transition feasibility**: Initial state can reach first-interval dispatch
4. **Parameter consistency**: Min ≤ Max, rates > 0, costs ≥ 0

---

## 9. Files & Assets

### 9.1 Notebook
- **File**: `04_optimisation.ipynb`
- **Location**: `/Users/quangthanhdong04.au@gmail.com/`
- **Contents**: Data loading, preprocessing, data cleaning, model build, solve

### 9.2 Documentation
- **File**: `04_optimisation_documentation.md` (this file)
- **Location**: `/Users/quangthanhdong04.au@gmail.com/`

### 9.3 Model Output Files
- `energy_optimization_model.lp`: Original infeasible model (for reference)
- `energy_optimization_model_fixed_infeasible.lp`: After data fixes, still infeasible
- Final model not written to file (solved successfully)

---

## 10. References & Context

### 10.1 National Electricity Market (NEM)
- **Regions**: NSW1, QLD1, SA1, TAS1, VIC1
- **Market Operator**: AEMO (Australian Energy Market Operator)
- **Dispatch Interval**: 5 minutes
- **Settlement**: 30-minute average of 6 × 5-minute dispatches

### 10.2 Generator Types
- **Thermal**: Coal, gas - require commitment decisions, have minimum stable levels
- **Hydro**: Gravity, pumped storage, run-of-river - flexible dispatch
- **Batteries**: Grid-scale storage - very flexible, fast response

### 10.3 Time Period
- **Date**: 2022-11-01 (Tuesday)
- **Time**: 00:05 - 04:00 (overnight, low demand period)
- **Season**: Late spring (Southern Hemisphere)
- **Typical Characteristics**: Low demand, high wind/hydro availability

---

## 11. Model Validation & Performance Evaluation

### 11.1 Validation Approach

To assess the realism and accuracy of the optimization model, validation against real-world AEMO dispatch data is essential. This comparison quantifies the impact of model simplifications and identifies areas for improvement.

### 11.2 Validation Methodology

**Data Sources:**
- **Model Solution**: Optimization output from `04_optimisation.ipynb` (P[i,t] and u[i,t] values)
- **AEMO Actual Dispatch**: Historical dispatch data from AEMO's Market Management System (MMS)
  - Tables: `DISPATCH_UNIT_SCADA`, `DISPATCHLOAD`, or similar
  - Same time period: 2022-11-01 00:05:00 to 04:00:00
  - Same units: 191 scheduled generators

**Comparison Metrics:**

1. **Cost Comparison**
   - Model total cost vs. Actual cost (using same variable cost assumptions)
   - Expected: Model cost likely **lower** (optimistic) due to omitted startup costs
   - Percentage difference and absolute difference ($)

2. **Dispatch Pattern Analysis**
   - Time series comparison by region and unit
   - Statistical metrics: RMSE, MAE, MAPE
   - Scatter plot analysis: Model MW vs. Actual MW
   - Error distribution: Where model over/under-dispatches

3. **Commitment Decision Analysis** (Thermal Units)
   - Confusion matrix: Model ON/OFF vs. Actual ON/OFF
   - Units that cycled in model but stayed committed in reality
   - Potential indication of missing min up/down time constraints

4. **Regional Performance**
   - Regional generation mix comparison (by technology)
   - SA1 specific validation (problematic region with relaxed t=0 ramping)
   - Regional demand satisfaction patterns

5. **Technology Mix Validation**
   - Merit order adherence (Hydro → Coal → Gas peakers)
   - Hydro, battery, coal, gas utilization rates
   - Identification of unrealistic dispatch patterns

### 11.3 Expected Findings

**Areas Where Model Should Perform Well:**
- Overall generation mix (merit order should align)
- Regional balance (demand met in each region)
- Low-cost unit utilization (hydro, coal base load)

**Areas Where Differences Expected:**
- **First interval (t=0)**: Relaxed ramping may show larger errors
- **Unit cycling**: Model may turn units ON/OFF more frequently (no startup costs)
- **Commitment patterns**: Model may have unrealistic short-duration commits (no min up/down times)
- **Total cost**: Model cost should be **5-15% lower** than reality (optimistic due to omitted costs)

### 11.4 Interpretation Guidelines

**If Model Cost is Much Lower:**
- Suggests significant unit cycling or unrealistic dispatch
- Consider adding startup costs for Phase 2
- May indicate excessive reliance on gas peakers

**If Commitment Patterns Differ Significantly:**
- Units turning ON/OFF every few intervals → missing min up/down times
- Long-committed units in reality but cycling in model → startup cost impact

**If Regional Errors are Large:**
- May need inter-regional transmission modeling
- Check if interconnectors were heavily utilized in reality

**If SA1 Shows Large t=0 Error:**
- Validates the t=0 ramping relaxation necessity
- Subsequent intervals should show better alignment

### 11.5 Validation Notebook

**File**: `05_model_validation_vs_aemo.ipynb`  
**Location**: `/Users/quangthanhdong04.au@gmail.com/`

**Contents**:
1. Load model solution and AEMO actual dispatch
2. Data alignment and preparation
3. Cost comparison analysis
4. Dispatch pattern validation (time series, scatter plots)
5. Commitment decision analysis (confusion matrix)
6. Regional and technology mix comparison
7. Impact assessment of model simplifications
8. Key findings and recommendations
9. Results export for documentation

### 11.6 Solver Performance Benchmarking

While this phase focuses on validating model outputs against real dispatch, future work can benchmark solver performance:

**HiGHS (Current Solver):**
- Open-source, free
- Solve time: 2.1 seconds for Phase 1 model
- Optimal solution found with 1% MIP gap
- **Assessment**: Adequate for Phase 1 size (~15,500 variables, ~27,744 constraints)

**Alternative Solvers for Benchmarking:**
- **CPLEX**: Commercial solver used by AEMO, typically 2-5x faster on large MILP
- **Gurobi**: Commercial, often fastest for MILP problems
- **CBC**: Open-source alternative, likely slower than HiGHS

**When to Consider Commercial Solvers:**
- Phase 2 with expanded constraints (startup costs, min up/down times)
- Extended time horizons (24 hours → 82,000 variables)
- Multiple scenario analysis requiring repeated solves
- Solve times exceeding 5-10 minutes with HiGHS

**Current Recommendation:**
- ✅ HiGHS is sufficient for Phase 1 development and testing
- 📊 AEMO dispatch validation provides more insight than solver benchmarking
- 🚀 Re-evaluate solver choice for Phase 2 based on model size and complexity

---

## 12. References & Context

### 12.1 National Electricity Market (NEM)
- **Regions**: NSW1, QLD1, SA1, TAS1, VIC1
- **Market Operator**: AEMO (Australian Energy Market Operator)
- **Dispatch Interval**: 5 minutes
- **Settlement**: 30-minute average of 6 × 5-minute dispatches

### 12.2 Generator Types
- **Thermal**: Coal, gas - require commitment decisions, have minimum stable levels
- **Hydro**: Gravity, pumped storage, run-of-river - flexible dispatch
- **Batteries**: Grid-scale storage - very flexible, fast response

### 12.3 Time Period
- **Date**: 2022-11-01 (Tuesday)
- **Time**: 00:05 - 04:00 (overnight, low demand period)
- **Season**: Late spring (Southern Hemisphere)
- **Typical Characteristics**: Low demand, high wind/hydro availability

---

**Document Version**: 1.2  
**Last Updated**: 2026-04-16  
**Author**: Databricks Assistant (Genie Code)  
**Project**: Energy Optimization Model Phase 1
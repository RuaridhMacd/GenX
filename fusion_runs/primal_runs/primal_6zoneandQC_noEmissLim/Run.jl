using GenX
using JuMP
using OrderedCollections
using DataFrames
using CSV

## Load helper functions
include(joinpath(pwd(),"fusion_runs","run_helpers.jl"))

## Define input and output paths
inputs_path = joinpath(pwd(),"fusion_runs","data","primal_6zoneandQC_baseline")
case_path = dirname(@__FILE__)

## Load settings
genx_settings = get_settings_path(inputs_path, "genx_settings.yml") #Settings YAML file path
mysetup = configure_settings(genx_settings) # mysetup dictionary stores settings and GenX-specific parameters
settings_path = get_settings_path(inputs_path)

## Cluster time series inputs if necessary and if specified by the user
TDRpath = joinpath(inputs_path, mysetup["TimeDomainReductionFolder"])
if mysetup["TimeDomainReduction"] == 1
    if !time_domain_reduced_files_exist(TDRpath)
        println("Clustering Time Series Data (Grouped)...")
        cluster_inputs(inputs_path, settings_path, mysetup)
    else
        println("Time Series Data Already Clustered.")
    end
end

## Configure solver
println("Configuring Solver")
OPTIMIZER = configure_solver(mysetup["Solver"], settings_path)
set_optimizer_attribute(OPTIMIZER, "BarHomogeneous", 1)

#### Running a case
# emiss_lim_list = 100.0 .* [2.5, 5, 10, 15, 20, 25, 1.0]
emiss_lim_list = 100000000.0

# This has to be set before loading inputs, otherwise a CO2 cap will be created regardless
mysetup["CO2Cap"] = 0
scale_factor = mysetup["ParameterScale"] == 1 ? ModelScalingFactor : 1

## Load inputs
println("Loading Inputs")
myinputs = load_inputs(mysetup, inputs_path)

for emiss_lim in emiss_lim_list

    # Hard-coded to put all emissions in New Hampshire, but CO2 Cap is set to be system-wide
    # myinputs["dfMaxCO2"][3] = emiss_lim * 1e3 / scale_factor
    outputs_path = joinpath(case_path, "Results", "Primal_Baseline_noEmissLim")

    # if isfile(joinpath(outputs_path, "costs.csv"))
    #     println("Skipping Case for no emiss lim case because it already exists.")
    #     continue
    # end

    mkpath(outputs_path)
    
    ## Generate model
    println("Generating the Optimization Model")
    EP = generate_model(mysetup, myinputs, OPTIMIZER)

    ########################
    #### Add any additional constraints
    HYDRO_RES = myinputs["HYDRO_RES"]
    dfGen = myinputs["dfGen"]

    ## Hydro storage <= 0.55 * Existing Capacity at start of May 1st 
    @constraint(EP, cHydroSpring[y in HYDRO_RES], EP[:vS_HYDRO][y, 2879] .<= 0.55 .* EP[:eTotalCap][y] .* dfGen[y,:Hydro_Energy_to_Power_Ratio]) 

    ## Hydro storage == 0.70 * Existing Capacity at the start of the year
    @constraint(EP, cHydroJan[y in HYDRO_RES], EP[:vS_HYDRO][y, 1]       .== 0.70 .* EP[:eTotalCap][y] .* dfGen[y,:Hydro_Energy_to_Power_Ratio]) 

    ## Maine -> Quebec transmission limited to 2170MWe.
    # The line is defined as Quebec -> Maine in Network.csv, so these flows will be negative
    # Make sure to correc the line index if the order is changed in Network.csv
    @constraint(EP, cMaine2Quebec[t=1:myinputs["T"]], EP[:vFLOW][1, t] >= -2170.0)
    ########################

    ## Solve model
    println("Solving Model")
    EP, solve_time = solve_model(EP, mysetup)
    myinputs["solve_time"] = solve_time # Store the model solve time in myinputs

    ## Run MGA if the MGA flag is set to 1 else only save the least cost solution
    println("Writing Output")
    # outputs_path = get_default_output_folder(outputs_path)

    ## Write outputs
    write_outputs(EP, outputs_path, mysetup, myinputs)

end
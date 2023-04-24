using GenX
using JuMP
using OrderedCollections
using DataFrames
using CSV

## Load helper functions
include(joinpath(pwd(),"fusion_runs","run_helpers.jl"))

## Define input and output paths
inputs_path = joinpath(pwd(),"fusion_runs","data","primal_6zoneandQC_baseline")
outputs_path = dirname(@__FILE__)

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

## Load inputs
println("Loading Inputs")
myinputs = load_inputs(mysetup, inputs_path)

## Generate model
println("Generating the Optimization Model")
EP = generate_model(mysetup, myinputs, OPTIMIZER)

#### Add any additional constraints
HYDRO_RES = myinputs["HYDRO_RES"]
dfGen = myinputs["dfGen"]

## Hydro storage <= 0.55 * Existing Capacity at start of May 1st 
@constraint(EP, cHydroSpring[y in HYDRO_RES], EP[:vS_HYDRO][y, 2879] .<= 0.55 .* EP[:eTotalCap][y] .* dfGen[y,:Hydro_Energy_to_Power_Ratio]) 

## Hydro storage == 0.70 * Existing Capacity at the start of the year
@constraint(EP, cHydroJan[y in HYDRO_RES], EP[:vS_HYDRO][y, 1]       .== 0.70 .* EP[:eTotalCap][y] .* dfGen[y,:Hydro_Energy_to_Power_Ratio]) 

## Solve model
println("Solving Model")
EP, solve_time = solve_model(EP, mysetup)
myinputs["solve_time"] = solve_time # Store the model solve time in myinputs

## Run MGA if the MGA flag is set to 1 else only save the least cost solution
println("Writing Output")
outputs_path = get_default_output_folder(outputs_path)

## Write outputs
write_outputs(EP, outputs_path, mysetup, myinputs)
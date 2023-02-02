"""
GenX: An Configurable Capacity Expansion Model
Copyright (C) 2021,  Massachusetts Institute of Technology
This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.
This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.
A complete copy of the GNU General Public License v2 (GPLv2) is available
in LICENSE.txt.  Users uncompressing this from an archive may not have
received this license file.  If not, see <http://www.gnu.org/licenses/>.
"""


### This function will initialize the key variables in the fusion module 
function fusionthermalpower(EP::Model, inputs::Dict, setup::Dict)

    dfGen = inputs["dfGen"]

    T = inputs["T"]     # Number of time steps (hours)

    FUSION = inputs["FUSION"]
    COMMIT = inputs["COMMIT"] # For now, thermal resources are the only ones eligible for Unit Committment

	### Variables ###

	## Decision variables for unit commitment
	# commitment state variable

    ## Expression to represent the commitment state of the fusion power generators
    @expression(EP, eFusionCommit[y in FUSION, t=1:T], EP[:vCOMMIT][y,t])

    # ## Initialize the variable for the reactor being on/standby (CAN probably find a way to call the inputs to get this value - most likely the COMMIT variable)
    # @variable(EP, fusioncommit[t=1:T], Bin)

    ## Fusion Power Nameplate Capacity
    NameplateCap = dfGen[!,:Cap_Size]/0.4   ## Divide by efficiency to convert to thermal power 

    ## Convert nameplate capacity to effective thermal power capacity
    # Effective capacity is a constant fraction of the nameplate capacity
    # Formula is as follows: Effective Cap = NameplateCap*(Reactor Pulse Time/(Reactor Pulse Time + Dwell Time))
    # Dwell Time is 1 minute and reactor pulse time is 20 minutes
    @expression(EP, eEffectiveCap[y in FUSION], NameplateCap[y]*(20/21))

    ## Reactor Thermal Output
    @variable(EP, vThermOutput[y in FUSION,t=1:T] >= 0)

    ## Constrain the Thermal Output with the Effective Capacity
    @constraint(EP, [y in FUSION,t=1:T], eEffectiveCap[y]*eFusionCommit[y,t] >= vThermOutput[y,t])
end

### This function will calculate the power provided by the reactor to the grid
function fusiongridpower(EP::Model, inputs::Dict, setup::Dict)
    T = inputs["T"]     # Number of time steps (hours)
    
    FUSION = inputs["FUSION"]

    ## Define key variables
    magcool = 10  #Amount of power (MW) being delivered to cool the magnets

    @expression(EP, eplantfix[y in FUSION,t=1:T], 10*EP[:eFusionCommit][y,t])  # Fixed power being delivered to the power plant (Number multiplied with the binary variable for start)
    @expression(EP, eplantvar[y in FUSION,t=1:T], (1/12)*EP[:vThermOutput][y,t])  # Variable power being delivered to the power plant (Function of the ThermalOutput of the power plant)
    
    @expression(EP, esaltpwr[y in FUSION,t=1:T], 10)  # Power being used to heat the salt 

    ## Combine to make recirculating power expression
    @expression(EP, eRecircpwr[y in FUSION,t=1:T], magcool + eplantfix[y,t] + eplantvar[y,t] + esaltpwr[y,t])

    ### Calculation for the thermal balance of the salt loop
    salteff = 0.2      ## Salt electric heating efficiency

    saltLosses = 2     ## Hourly Thermal losses from salt loop (2 MW/hr)

    ## Expression for the thermal energy entering the turbine 
    @expression(EP, eTurbThermal[y in FUSION,t=1:T], esaltpwr[y,t]*salteff + EP[:vThermOutput][y,t] - saltLosses)

    ## Define the turbine efficiency
    turbeff = 0.40 #(Change out for heat rate in gen_data)

    ## Expression for the total amount of power delivered by the power plants to the grid
    @expression(EP, eFusionPower[y in FUSION,t=1:T], eTurbThermal[y,t]*turbeff - eRecircpwr[y,t])
    
    @constraint(EP, [y in FUSION, t=1:T], eFusionPower[y,t] == EP[:vP][y,t])
end


## This function is the overall function for fusion power 
function fusion!(EP::Model, inputs::Dict, setup::Dict)
    fusionthermalpower(EP,inputs,setup)
    fusiongridpower(EP,inputs,setup)
end
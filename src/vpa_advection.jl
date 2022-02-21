module vpa_advection

export vpa_advection!
export update_speed_vpa!

using ..semi_lagrange: find_approximate_characteristic!
using ..advection: update_boundary_indices!
using ..advection: advance_f_local!
using ..communication
using ..calculus: derivative!
using ..initial_conditions: enforce_vpa_boundary_condition!
using ..looping

function vpa_advection!(f_out, fvec_in, ff, fields, moments, SL, advect,
        vpa, vperp, z, r, use_semi_lagrange, dt, t,
        vpa_spectral, z_spectral, composition, CX_frequency, istage)

    # only have a parallel acceleration term for neutrals if using the peculiar velocity
    # wpar = vpar - upar as a variable; i.e., d(wpar)/dt /=0 for neutrals even though d(vpar)/dt = 0.

    # calculate the advection speed corresponding to current f
    update_speed_vpa!(advect, fields, fvec_in, moments, vpa, vperp,
    z, r, composition, CX_frequency, t, z_spectral)
    @loop_s is begin
        if !moments.evolve_upar && is in composition.neutral_species_range
            # No acceleration for neutrals when not evolving upar
            continue
        end
        # update the upwind/downwind boundary indices and upwind_increment
        # NB: not sure if this will work properly with SL method at the moment
        # NB: if the speed is actually time-dependent
        update_boundary_indices!(advect[is], loop_ranges[].vperp, loop_ranges[].z, loop_ranges[].r)
        # if using interpolation-free Semi-Lagrange,
        # follow characteristics backwards in time from level m+1 to level m
        # to get departure points.  then find index of grid point nearest
        # the departure point at time level m and use this to define
        # an approximate characteristic
        if use_semi_lagrange
            # NOT SUPPORTED in semi_lagrange module
            @loop_r_z_vperp ir iz ivperp begin
                find_approximate_characteristic!(SL, advect[is], ivperp, iz, ir, vpa, dt)
            end
        end
        @loop_r_z_vperp ir iz ivperp begin
            @views advance_f_local!(f_out[:,ivperp,iz,ir,is], fvec_in.pdf[:,ivperp,iz,ir,is],
                                    ff[:,ivperp,iz,ir,is],
                                    SL, advect[is], ivperp, iz, ir, vpa, dt, istage,
                                    vpa_spectral, use_semi_lagrange)
        end
        #@views enforce_vpa_boundary_condition!(f_out[:,:,is], vpa.bc, advect[is])
    end
end
# calculate the advection speed in the z-direction at each grid point
function update_speed_vpa!(advect, fields, fvec, moments, vpa, vperp, z, r, composition, CX_frequency, t, z_spectral)
    @boundscheck r.n == size(advect[1].speed,4) || throw(BoundsError(advect))
    @boundscheck z.n == size(advect[1].speed,3) || throw(BoundsError(advect))
    @boundscheck vperp.n == size(advect[1].speed,2) || throw(BoundsError(advect))
    #@boundscheck composition.n_ion_species == size(advect,2) || throw(BoundsError(advect))
    @boundscheck composition.n_species == size(advect,1) || throw(BoundsError(advect))
    @boundscheck vpa.n == size(advect[1].speed,1) || throw(BoundsError(speed))
    if vpa.advection.option == "default"
        # dvpa/dt = Ze/m ⋅ E_parallel
        update_speed_default!(advect, fields, fvec, moments, vpa, vperp, z, r, composition, CX_frequency, t, z_spectral)
    elseif vpa.advection.option == "constant"
        @serial_region begin
            # Not usually used - just run in serial
            #
            # dvpa/dt = constant
            s_range = ifelse(moments.evolve_upar, 1:composition.n_species,
                             composition.ion_species_range)
            for is ∈ s_range
                update_speed_constant!(advect[is], vpa, 1:vperp.n, 1:z.n, 1:r.n)
            end
        end
        block_sychronize()
    elseif vpa.advection.option == "linear"
        @serial_region begin
            # Not usually used - just run in serial
            #
            # dvpa/dt = constant ⋅ (vpa + L_vpa/2)
            s_range = ifelse(moments.evolve_upar, 1:composition.n_species,
                             composition.ion_species_range)
            for is ∈ s_range
                update_speed_linear!(advect[is], vpa, 1:vperp.n, 1:z.n, 1:r.n)
            end
        end
        block_sychronize()
    end
    @loop_s is begin
        if !moments.evolve_upar && is in composition.neutral_species_range
            # No acceleration for neutrals when not evolving upar
            continue
        end
        @loop_r_z_vperp ir iz ivperp begin
            @views @. advect[is].modified_speed[:,ivperp,iz,ir] = advect[is].speed[:,ivperp,iz,ir]
        end
    end
    return nothing
end
function update_speed_default!(advect, fields, fvec, moments, vpa, vperp, z, r, composition, CX_frequency, t, z_spectral)
    if moments.evolve_ppar
        @loop_s is begin
            @loop_r ir begin
                # get d(ppar)/dz
                derivative!(z.scratch, view(fvec.ppar,:,ir,is), z, z_spectral)
                # update parallel acceleration to account for parallel derivative of parallel pressure
                # NB: no vpa-dependence so compute as a scalar and broadcast to all entries
                @loop_z_vperp iz ivperp begin
                    @views advect[is].speed[:,ivperp,iz,ir] .= z.scratch[iz]/(fvec.density[iz,ir,is]*moments.vth[iz,ir,is])
                end
                # calculate d(qpar)/dz
                derivative!(z.scratch, view(moments.qpar,:,ir,is), z, z_spectral)
                # update parallel acceleration to account for (wpar/2*ppar)*dqpar/dz
                @loop_z_vperp iz ivperp begin
                    @views @. advect[is].speed[:,ivperp,iz,ir] += 0.5*vpa.grid*z.scratch[iz]/fvec.ppar[iz,ir,is]
                end
                # calculate d(vth)/dz
                derivative!(z.scratch, view(moments.vth,:,ir,is), z, z_spectral)
                # update parallel acceleration to account for -wpar^2 * d(vth)/dz term
                @loop_z_vperp iz ivperp begin
                    @views @. advect[is].speed[:,ivperp,iz,ir] -= vpa.grid^2*z.scratch[iz]
                end
            end
        end
        # add in contributions from charge exchange collisions
        if composition.n_neutral_species > 0 && abs(CX_frequency) > 0.0
            @loop_s is begin
                if is ∈ composition.ion_species_range
                    for isp ∈ composition.neutral_species_range
                        @loop_r_z_vperp ir iz ivperp begin
                            @views @. advect[is].speed[:,ivperp,iz,ir] += CX_frequency *
                            (0.5*vpa.grid/fvec.ppar[iz,ir,is] * (fvec.density[iz,ir,isp]*fvec.ppar[iz,ir,is]
                                                              - fvec.density[iz,ir,is]*fvec.ppar[iz,ir,isp])
                             - fvec.density[iz,ir,isp] * (fvec.upar[iz,ir,isp]-fvec.upar[iz,ir,is])/moments.vth[iz,ir,is])
                        end
                    end
                end
                if is ∈ composition.neutral_species_range
                    for isp ∈ composition.ion_species_range
                        @loop_r_z_vperp ir iz ivperp begin
                            @views @. advect[is].speed[:,ivperp,iz,ir] += CX_frequency *
                            (0.5*vpa.grid/fvec.ppar[iz,ir,is] * (fvec.density[iz,ir,isp]*fvec.ppar[iz,ir,is]
                                                              - fvec.density[iz,ir,is]*fvec.ppar[iz,ir,isp])
                             - fvec.density[iz,ir,isp] * (fvec.upar[iz,ir,isp]-fvec.upar[iz,ir,is])/moments.vth[iz,ir,is])
                        end
                    end
                end
            end
        end
    elseif moments.evolve_upar
        @loop_s is begin
            @loop_r ir begin
                # get d(ppar)/dz
                derivative!(z.scratch, view(fvec.ppar,:,ir,is), z, z_spectral)
                # update parallel acceleration to account for parallel derivative of parallel pressure
                # NB: no vpa-dependence so compute as a scalar and broadcast to all entries
                @loop_z_vperp iz ivperp begin
                    @views advect[is].speed[:,ivperp,iz,ir] .= z.scratch[iz]/fvec.density[iz,ir,is]
                end
                # calculate d(upar)/dz
                derivative!(z.scratch, view(fvec.upar,:,ir,is), z, z_spectral)
                # update parallel acceleration to account for -wpar*dupar/dz
                @loop_z_vperp iz ivperp begin
                    @views @. advect[is].speed[:,ivperp,iz,ir] -= vpa.grid*z.scratch[iz]
                end
            end
        end
        # if neutrals present and charge exchange frequency non-zero,
        # account for collisional friction between ions and neutrals
        if composition.n_neutral_species > 0 && abs(CX_frequency) > 0.0
            # include contribution to ion acceleration due to collisional friction with neutrals
            @loop_s is begin
                if is ∈ composition.ion_species_range
                    for isp ∈ composition.neutral_species_range
                        @loop_r_z_vperp ir iz ivperp begin
                            @views advect[is].speed[:,ivperp,iz,ir] .+= -CX_frequency*fvec.density[iz,ir,isp]*(fvec.upar[iz,ir,isp]-fvec.upar[iz,ir,is])
                        end
                    end
                end
                # include contribution to neutral acceleration due to collisional friction with ions
                if is ∈ composition.neutral_species_range
                    for isp ∈ composition.ion_species_range
                        # get the absolute species index for the neutral species
                        @loop_r_z_vperp ir iz ivperp begin
                            @views advect[is].speed[:,ivperp,iz,ir] .+= -CX_frequency*fvec.density[iz,ir,isp]*(fvec.upar[iz,ir,isp]-fvec.upar[iz,ir,is])
                        end
                    end
                end
            end
        end
    else
        @inbounds @fastmath begin
            @loop_s is begin
                if !moments.evolve_upar && is in composition.neutral_species_range
                    # No acceleration for neutrals when not evolving upar
                    continue
                end
                @loop_r ir begin
                    # update the electrostatic potential phi
                    # calculate the derivative of phi with respect to z;
                    # the value at element boundaries is taken to be the average of the values
                    # at neighbouring elements
                    derivative!(z.scratch, view(fields.phi,:,ir), z, z_spectral)
                    # advection velocity in vpa is -dphi/dz = -z.scratch
                    @loop_z_vperp iz ivperp begin
                        @views advect[is].speed[:,ivperp,iz,ir] .= -0.5*z.scratch[iz]
                    end
                end
            end
        end
    end
end
# update the advection speed dvpa/dt = constant
function update_speed_constant!(advect, vpa, vperp_range, z_range, r_range)
    #@inbounds @fastmath begin
    for ir ∈ r_range
        for iz ∈ z_range
            for ivperp ∈ vperp_range
                @views advect.speed[:,ivperp,iz,ir] .= vpa.advection.constant_speed
            end
        end
    end
    #end
end
# update the advection speed dvpa/dt = const*(vpa + L/2)
function update_speed_linear(advect, vpa, z_range, r_range)
    @inbounds @fastmath begin
        for ir ∈ r_range
            for iz ∈ z_range
                for ivperp ∈ vperp_range
                    @views @. advect.speed[:,ivperp,iz,ir] = vpa.advection.constant_speed*(vpa.grid+0.5*vpa.L)
                end
            end
        end
    end
end

end

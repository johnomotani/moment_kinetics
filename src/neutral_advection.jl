"""
"""
module neutral_advection

export neutral_advection_r!
export update_speed_neutral_r!
export neutral_advection_z!
export update_speed_neutral_z!

using ..advection: advance_f_df_precomputed!, update_boundary_indices!
using ..chebyshev: chebyshev_info
using ..looping
using ..derivatives: derivative_r!, derivative_z!

"""
do a single stage time advance in r (potentially as part of a multi-stage RK scheme)
"""
function neutral_advection_r!(f_out, fvec_in, advect, r, z, vzeta, vr, vz, dt,
  r_spectral, composition, geometry, scratch_dummy)
    
    begin_sn_z_vzeta_vr_vz_region()
    
    @loop_sn isn begin
        # get the updated speed along the r direction using the current f
        @views update_speed_neutral_r!(advect[isn], r, z, vzeta, vr, vz)
        # update the upwind/downwind boundary indices and upwind_increment
        @views update_boundary_indices!(advect[isn], loop_ranges[].vz, loop_ranges[].vr, loop_ranges[].vzeta, loop_ranges[].z)
        # update adv_fac
        advect[isn].adv_fac[:,:,:,:,:] .= -dt.*advect[isn].speed[:,:,:,:,:]
		# calculate the upwind derivative along r
        derivative_r!(scratch_dummy.buffer_vzvrvzetazr,fvec_in.pdf_neutral[:,:,:,:,:,isn], advect[isn].adv_fac[:,:,:,:,:],
					scratch_dummy.buffer_vzvrvzetaz_1, scratch_dummy.buffer_vzvrvzetaz_2,
					scratch_dummy.buffer_vzvrvzetaz_3,scratch_dummy.buffer_vzvrvzetaz_4,
					scratch_dummy.buffer_vzvrvzetaz_5,scratch_dummy.buffer_vzvrvzetaz_6,
					r_spectral,r)

        # advance r-advection equation
        @loop_z_vzeta_vr_vz iz ivzeta ivr ivz begin
            @. r.scratch = scratch_dummy.buffer_vzvrvzetazr[ivz,ivr,ivzeta,iz,:]
            @views advance_f_df_precomputed!(f_out[ivz,ivr,ivzeta,iz,:,isn],
			  r.scratch, advect[isn], ivz, ivr, ivzeta, iz, r, dt, r_spectral)
        end
    end
end


"""
calculate the advection speed in the r-direction at each grid point
"""
function update_speed_neutral_r!(advect, r, z, vzeta, vr, vz)
    @boundscheck z.n == size(advect.speed,5) || throw(BoundsError(advect))
    @boundscheck vzeta.n == size(advect.speed,4) || throw(BoundsError(advect))
    @boundscheck vr.n == size(advect.speed,3) || throw(BoundsError(advect))
    @boundscheck vz.n == size(advect.speed,2) || throw(BoundsError(advect))
    @boundscheck r.n == size(advect.speed,1) || throw(BoundsError(speed))
    if r.advection.option == "default" && r.n > 1
        @inbounds begin
            @loop_z_vzeta_vr_vz iz ivzeta ivr ivz begin
                @views advect.speed[:,ivz,ivr,ivzeta,iz] .= vr.grid[ivr]
            end
        end
    elseif r.advection.option == "default" && r.n == 1 
        # no advection if no length in r 
        @loop_z_vzeta_vr_vz iz ivzeta ivr ivz begin
            advect.speed[:,ivz,ivr,ivzeta,iz] .= 0.
        end
    end
    
    # the default for modified_speed is simply speed.
    @inbounds begin
        @loop_z_vzeta_vr_vz iz ivzeta ivr ivz begin
            @views advect.modified_speed[:,ivz,ivr,ivzeta,iz] .= advect.speed[:,ivz,ivr,ivzeta,iz] 
        end
    end
    return nothing
end

"""
do a single stage time advance in z (potentially as part of a multi-stage RK scheme)
"""
function neutral_advection_z!(f_out, fvec_in, advect, r, z, vzeta, vr, vz, dt,
  z_spectral, composition, geometry, scratch_dummy)
    
    begin_sn_r_vzeta_vr_vz_region()
    
    @loop_sn isn begin
        # get the updated speed along the r direction using the current f
        @views update_speed_neutral_z!(advect[isn], r, z, vzeta, vr, vz)
        # update the upwind/downwind boundary indices and upwind_increment
        @views update_boundary_indices!(advect[isn], loop_ranges[].vz, loop_ranges[].vr, loop_ranges[].vzeta, loop_ranges[].r)
        # update adv_fac
        advect[isn].adv_fac[:,:,:,:,:] .= -dt.*advect[isn].speed[:,:,:,:,:]
		# calculate the upwind derivative along z
        derivative_z!(scratch_dummy.buffer_vzvrvzetazr,fvec_in.pdf_neutral[:,:,:,:,:,isn], advect[isn].adv_fac[:,:,:,:,:],
					scratch_dummy.buffer_vzvrvzetar_1, scratch_dummy.buffer_vzvrvzetar_2,
					scratch_dummy.buffer_vzvrvzetar_3,scratch_dummy.buffer_vzvrvzetar_4,
					scratch_dummy.buffer_vzvrvzetar_5,scratch_dummy.buffer_vzvrvzetar_6,
					z_spectral,z)

        # advance z-advection equation
        @loop_r_vzeta_vr_vz ir ivzeta ivr ivz begin
            @. z.scratch = scratch_dummy.buffer_vzvrvzetazr[ivz,ivr,ivzeta,:,ir]
            @views advance_f_df_precomputed!(f_out[ivz,ivr,ivzeta,:,ir,isn],
			  z.scratch, advect[isn], ivz, ivr, ivzeta, ir, z, dt, z_spectral)
        end
    end
end


"""
calculate the advection speed in the z-direction at each grid point
"""
function update_speed_neutral_z!(advect, r, z, vzeta, vr, vz)
    @boundscheck r.n == size(advect.speed,5) || throw(BoundsError(advect))
    @boundscheck vzeta.n == size(advect.speed,4) || throw(BoundsError(advect))
    @boundscheck vr.n == size(advect.speed,3) || throw(BoundsError(advect))
    @boundscheck vz.n == size(advect.speed,2) || throw(BoundsError(advect))
    @boundscheck z.n == size(advect.speed,1) || throw(BoundsError(speed))
    if z.advection.option == "default" && z.n > 1
        @inbounds begin
            @loop_r_vzeta_vr_vz ir ivzeta ivr ivz begin
                @views advect.speed[:,ivz,ivr,ivzeta,ir] .= vz.grid[ivz]
            end
        end
    elseif z.advection.option == "default" && z.n == 1 
        # no advection if no length in r 
        @loop_r_vzeta_vr_vz ir ivzeta ivr ivz begin
            advect.speed[:,ivz,ivr,ivzeta,ir] .= 0.
        end
    end
    
    # the default for modified_speed is simply speed.
    @inbounds begin
        @loop_r_vzeta_vr_vz ir ivzeta ivr ivz begin
            @views advect.modified_speed[:,ivz,ivr,ivzeta,ir]  .= advect.speed[:,ivz,ivr,ivzeta,ir] 
        end
    end
    return nothing
end


end

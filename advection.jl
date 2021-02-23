module advection

export setup_source
export update_advection_factor!
export calculate_explicit_source!
export update_boundary_indices!
export set_igrid_ilem
export advance_f_local!

using type_definitions: mk_float, mk_int
using array_allocation: allocate_float
using finite_differences: derivative_finite_difference!
using chebyshev: chebyshev_derivative!
using chebyshev: chebyshev_info

# structure containing the basic arrays associated with the
# source terms appearing in the advection equation for each coordinate
mutable struct source_info
    # rhs is the sum of the source terms appearing on the righthand side
    # of the equation
    rhs::Array{mk_float, 1}
    # df is the derivative of the distribution function f with respect
    # to the coordinate associated with this set of source terms
    # it has dimensions of nelement x ngrid_per_element
    df::Array{mk_float, 2}
    # speed is the component of the advection speed along this coordinate axis
    speed::Array{mk_float, 1}
    # if using semi-Lagrange approach,
    # modified_speed is delta / dt, where delta for a given characteristic
    # is the displacement from the arrival point to the
    # (generally off-grid) departure point using the coordinate in which
    # the grid is equally spaced (a re-scaling of the Chebyshev theta coordinate);
    # otherwise, modified_speed = speed
    modified_speed::Array{mk_float,1}
    # adv_fac is the advection factor that multiplies df in the advective source
    adv_fac::Array{mk_float, 1}
    # upwind_idx is the boundary index for the upwind boundary
    upwind_idx::mk_int
    # downwind_idx is the boundary index for the downwind boundary
    downwind_idx::mk_int
    # upwind_increment is the index increment used when sweeping in the upwind direction
    upwind_increment::mk_int
end
# create arrays needed to compute the source term(s) for a 1D problem
function setup_source(coord, nspec)
    # allocate an array containing structures with much of the info needed
    # to do the 1D advection time advance
    source = Array{source_info,1}(undef, nspec)
    # store all of this information in a structure and return it
    for is ∈ 1:nspec
        source[is] = setup_source_local(coord.n, coord.ngrid, coord.nelement)
    end
    return source
end
# create arrays needed to compute the source term(s) for a 2D problem
function setup_source(coord1, coord2, nspec)
    # n and m are the number of unique grid points along coordinates coord1 and coord2
    n = coord1.n
    m = coord2.n
    # allocate an array containing structures with much of the info needed
    # to do the 1D advection time advance
    source = Array{source_info,2}(undef, m, nspec)
    # store all of this information in a structure and return it
    for is ∈ 1:nspec
        for i ∈ 1:m
            source[i,is] = setup_source_local(coord1.n, coord1.ngrid, coord1.nelement)
        end
    end
    return source
end
#=
# create arrays needed to compute the source term(s) for a 1D problem
function setup_source(coord)
    return setup_source_local(coord.n, coord.ngrid, coord.nelement)
end
# create arrays needed to compute the source term(s) for a 2D problem
function setup_source(coord1, coord2)
    # n and m are the number of unique grid points along coordinates coord1 and coord2
    n = coord1.n
    m = coord2.n
    # allocate an array containing structures with much of the info needed
    # to do the 1D advection time advance
    source = Array{source_info,1}(undef, m)
    # store all of this information in a structure and return it
    for i ∈ 1:m
        source[i] = setup_source_local(coord1.n, coord1.ngrid, coord1.nelement)
    end
    return source
end
=#
# create arrays needed to compute the source term(s)
function setup_source_local(n, ngrid, nelement)
    # create array for storing the explicit source terms appearing
    # on the righthand side of the equation
    rhs = allocate_float(n)
    # create array for storing ∂f/∂(coordinate)
    # NB: need to store on nelement x ngrid_per_element array, as must keep info
    # about multi-valued derivative at overlapping point at element boundaries
    df = allocate_float(ngrid, nelement)
    # create array for storing the advection coefficient
    adv_fac = allocate_float(n)
    # create array for storing the speed along this coordinate
    speed = allocate_float(n)
    # create array for storing the modified speed along this coordinate
    modified_speed = allocate_float(n)
    # index for the upwind boundary; will be updated before use so value irrelevant
    upwind_idx = 1
    # index for the downwind boundary; will be updated before use so value irrelevant
    downwind_idx = n
    # index increment used when sweeping in the upwind direction; will be updated before use
    upwind_increment = -1
    # return source_info struct containing necessary 1D/0D arrays
    return source_info(rhs, df, speed, modified_speed, adv_fac, upwind_idx, downwind_idx, upwind_increment)
end
# calculate the grid index correspond to the upwind and downwind boundaries,
# as well as the index increment needed to sweep in the upwind direction
function update_boundary_indices!(source)
    m = size(source,1)
    n = size(source[1].speed,1)
    for j ∈ 1:m
        # NB: for now, assume the speed has the same sign at all grid points
        # so only need to check its value at one location to determine the upwind direction
        if source[j].speed[1] > 0
            source[j].upwind_idx = 1
            source[j].upwind_increment = -1
            source[j].downwind_idx = n
        else
            source[j].upwind_idx = n
            source[j].upwind_increment = 1
            source[j].downwind_idx = 1
        end
    end
    return nothing
end
# calculate the factor appearing in front of f' in the advection term
# at time level n in the frame moving with the approximate characteristic
function update_advection_factor!(adv_fac, speed, upwind_idx, downwind_idx,
    upwind_increment, SL, n, dt, j, coord)
    @boundscheck n == length(SL.dep_idx) || throw(BoundsError(SL.dep_idx))
    @boundscheck n == length(adv_fac) || throw(BoundsError(adv_fac))
    @boundscheck n == length(speed) || throw(BoundsError(speed))
    @boundscheck n == length(SL.characteristic_speed) ||
        throw(BoundsError(SL.characteristic_speed))
    #NB: commented out line below needed for bc != periodic?
    #@inbounds for i ∈ upwind_idx-upwind_increment:-upwind_increment:downwind_idx
    @inbounds for i ∈ upwind_idx:-upwind_increment:downwind_idx
        idx = SL.dep_idx[i]
        # only need to calculate advection factor for characteristics
        # that originate within the domain, as zero/constant incoming BC
        # takes care of the rest.
        if idx != upwind_idx + upwind_increment
            # the effective advection speed appearing in the source
            # is the speed in the frame moving with the approximate
            # characteristic speed v_char
            # NB: need to change v[idx] to v[i] for second iteration of RK
            if j == 1
                adv_fac[i] = -dt*(speed[idx]-SL.characteristic_speed[i])
            elseif j == 2
                adv_fac[i] = -dt*(speed[i]-SL.characteristic_speed[i])
            end
        end
    end
    return nothing
end
# calculate the explicit source terms on the rhs of the equation;
# i.e., -Δt⋅δv⋅f'
function calculate_explicit_source!(rhs, df, adv_fac, up_idx, down_idx, up_incr,
    dep_idx, n, ngrid, nelement, igrid_map, ielement_map, j)
    # ensure that arrays needed for this function are inbounds
    # to avoid checking multiple times later
    @boundscheck n == length(rhs) || throw(BoundsError(rhs))
    @boundscheck ngrid == size(df,1) && nelement == size(df,2) || throw(BoundsError(df))
    @boundscheck n == length(adv_fac) || throw(BoundsError(adv_fac))
    @boundscheck n == length(dep_idx) || throw(BoundsError(dep_idx))
    # calculate the source evaluated at the departure point for the
    # ith characteristic.  note that adv_fac[i] has already
    # been defined so that it corresponds to the advection factor
    # corresponding to the ith characteristic
    if j == 1
        #@inbounds for i ∈ up_idx:-up_incr:down_idx
        @inbounds for i ∈ 1:n
            idx = dep_idx[i]

            if idx != up_idx + up_incr
                # if at the boundary point within the element, must carefully
                # choose which value of df to use; this is because
                # df is multi-valued at the overlapping point at the boundary
                # between neighboring elements.
                igrid, ielem = set_igrid_ielem(igrid_map[idx], ielement_map[idx],
                    adv_fac[i], ngrid, nelement)
                rhs[i] = adv_fac[i]*df[igrid,ielem]
            end
        end
    else
        #@inbounds for i ∈ up_idx:-up_incr:down_idx
        @inbounds for i ∈ 1:n
            # if at the boundary point within the element, must carefully
            # choose which value of df to use; this is because
            # df is multi-valued at the overlapping point at the boundary
            # between neighboring elements.
            igrid, ielem = set_igrid_ielem(igrid_map[i], ielement_map[i],
                adv_fac[i], ngrid, nelement)
            rhs[i] = adv_fac[i]*df[igrid,ielem]
        end
    end
    return nothing
end

function set_igrid_ielem(igrid_map, ielem_map, adv_fac, ngrid, nelement)
    # if at the boundary point within the element, must carefully
    # choose which value of df to use; this is because
    # df is multi-valued at the overlapping point at the boundary
    # between neighboring elements.
    # here we choose to use the value of df from the upwind element.

    # note that the first ngrid points are classified as belonging to the first element
    # and the next ngrid-1 points belonging to second element, etc.

    # adv_fac > 0 corresponds to negative advection speed, so
    # use derivative information from upwind element at larger coordinate value
    if igrid_map == ngrid && adv_fac > 0.0
        igrid = 1
        ielem = mod(ielem_map, nelement) + 1
    # adv_fac < 0 corresponds to positive advection speed, so
    # use derivative information from upwind element at smaller coordinate value
    elseif igrid_map == 1 && adv_fac < 0.0
        igrid = ngrid
        ielem = nelement - mod(nelement-ielem_map+1,nelement)
    # aside from above cases, the pre-computed mappings from unpacked index i
    # to element and grid within element indices are already correct
    else
        igrid = igrid_map
        ielem = ielem_map
    end
    return igrid, ielem
end

# update the righthand side of the equation to account for 1d advection in this coordinate
function update_rhs!(source, f_current, SL, coord, dt, j, spectral)
    # calculate the factor appearing in front of df/dcoord in the advection
    # term at time level n in the frame moving with the approximate
    # characteristic
    update_advection_factor!(source.adv_fac,
        source.modified_speed, source.upwind_idx, source.downwind_idx,
        source.upwind_increment, SL, coord.n, dt, j, coord)
    # calculate df/dcoord
    derivative!(source.df, f_current, coord, source.adv_fac, spectral)
    # calculate the explicit source terms on the rhs of the equation;
    # i.e., -Δt⋅δv⋅f'
    calculate_explicit_source!(source.rhs, source.df,
        source.adv_fac, source.upwind_idx, source.downwind_idx,
        source.upwind_increment, SL.dep_idx, coord.n, coord.ngrid, coord.nelement,
        coord.igrid, coord.ielement, j)
end
# Chebyshev transform f to get Chebyshev spectral coefficients and use them to calculate f'
function derivative!(df, f, coord, adv_fac, spectral::chebyshev_info)
    chebyshev_derivative!(df, f, spectral, coord)
end
# calculate the derivative of f using finite differences; stored in df
function derivative!(df, f, coord, adv_fac, not_spectral::Bool)
    derivative_finite_difference!(df, f, coord.cell_width, adv_fac,
        coord.bc, coord.fd_option, coord.igrid, coord.ielement)
end
# do all the work needed to update f(coord) at a single value of other coords
function advance_f_local!(f_new, f_current, f_old, SL, source, coord, dt, j, spectral, use_SL)
    # update the rhs of the equation accounting for 1d advection in coord
    update_rhs!(source, f_current, SL, coord, dt, j, spectral)
    # update ff at time level n+1 using an explicit Runge-Kutta method
    # along approximate characteristics
    update_f!(f_new, f_old, source.rhs, source.upwind_idx, source.downwind_idx,
        source.upwind_increment, SL.dep_idx, coord.n, coord.bc, use_SL)
end
# update ff at time level n+1 using an explicit Runge-Kutta method
# along approximate characteristics
function update_f!(f_new, f_old, rhs, up_idx, down_idx, up_incr, dep_idx, n, bc, use_SL)
    @boundscheck n == length(f_new) || throw(BoundsError(f_new))
    @boundscheck n == length(rhs) || throw(BoundsError(rhs))
    @boundscheck n == length(dep_idx) || throw(BoundsError(dep_idx))
    @boundscheck n == length(f_old) || throw(BoundsError(f_old))

    if use_SL
        # do not update the upwind boundary, where the constant incoming BC has been imposed
        if bc != "periodic"
            f_new[up_idx] = f_old[up_idx]
            istart = up_idx-up_incr
        else
            istart = up_idx
        end
        #@inbounds for i ∈ up_idx-up_incr:-up_incr:down_idx
        @inbounds for i ∈ up_idx:-up_incr:down_idx
            # dep_idx is the index of the departure point for the approximate
            # characteristic passing through grid point i
            # if semi-Lagrange is not used, then dep_idx = i
            idx = dep_idx[i]
            if idx != up_idx + up_incr
                f_new[i] = f_old[idx] + rhs[i]
            else
                # if departure index is beyond upwind boundary, then
                # set updated value along characteristic equal to the old
                # value at the boundary; i.e., assume f is constant
                # beyond the upwind boundary
                f_new[i] = f_old[up_idx]
            end
        end
    else
        @inbounds for i ∈ up_idx:-up_incr:down_idx
            f_new[i] += rhs[i]
        end
    end
    return nothing
end

end
module semi_lagrange

import array_allocation: allocate_float, allocate_int

export setup_semi_lagrange
export update_crossing_times!
export find_departure_points!
export project_characteristics_onto_grid!

# structure semi_lagrange_info contains the basic information needed
# to project backwards along approximate characteristics, which
# underpins the semi-Lagrange approach to time advancement
struct semi_lagrange_info
    # crossing_time is the time required to cross a given cell
    # moving at a specified advection speed
    crossing_time::Array{Float64,1}
    # trajectory_time is the cumulative trajectory time along a characteristic
    trajectory_time::Array{Float64,1}
    # dep_pts are the departure points at time level m for characteristic
    # arriving at time level m+1
    dep_pts::Array{Float64,1}
    # dep_idx are the indices of the nearest downwind grid point to
    # the departure point (which is in general between grid points)
    dep_idx::Array{Int64,1}
    # characteristic_speed is the approximate characteristic speed
    characteristic_speed::Array{Float64,1}
end
# create and return a structure containing the arrays needed for the
# semi-Lagrange time advance
function setup_semi_lagrange(n)
    return setup_semi_lagrange_local(n)
end
function setup_semi_lagrange(n, m)
    # allocate an array containing structures with the info needed
    # to do the semi-Lagrange time advance
    SL = Array{semi_lagrange_info,1}(undef, m)
    # store all of this information in a structure and return it
    for i ∈ 1:m
        SL[i] = setup_semi_lagrange_local(n)
    end
    return SL
end
# create and return a structure containing the arrays needed for the
# semi-Lagrange time advance
function setup_semi_lagrange_local(n)
    # create an array to hold crossing times for each cell
    crossing_time = allocate_float(n)
    # create an array to hold cumulative trajectory time for each characteristic
    trajectory_time = allocate_float(n)
    # create array for the departure points at time level m
    dep_pts = allocate_float(n)
    # create array for the indices of the nearest downwind grid point to
    # the departure point (which is in general between grid points)
    dep_idx = allocate_int(n)
    # initialize the departure indices to be the save as the arrival indices
    # this allows for a clean algorithm that can use semi-Lagrange or not
    # without a lot of conditional statements within inner loops
    for i ∈ 1:n
        dep_idx[i] = i
    end
    # create array containing approximate characteristic speed
    # initialize characteristic speed to zero, in case one wants to
    # do a time advance without use of semi-Lagrange treatment
    characteristic_speed = zeros(n)
    # store all of this information in a structure and return it
    return semi_lagrange_info(crossing_time, trajectory_time, dep_pts, dep_idx,
        characteristic_speed)
end
function find_approximate_characteristic!(SL, speed, coord, dt)
    # calculate the time required to cross the cell associated with each
    # grid point based on the cell width and advection speed
    update_crossing_times!(SL.crossing_time, speed, coord.cell_width)
    # integrate backward in time from time level m+1 to level m
    # along approximate characteristics determined by speed profile at level m
    # to obtain departure points.  these will not correspond
    # in general to grid points at time level m
    find_departure_points!(SL, coord, speed, dt)
    # redefine v₀ slightly so
    # that departure point corresonds to nearest grid point
    # this avoids the need to do interpolation to obtain
    # function values off the fixed grid in z
    project_characteristics_onto_grid!(SL, coord, dt)
end
# obtain the time needed to cross the cell
# assigned to each grid point, given the
# advection speed within the cell
# NB: assuming constant advection speed within each cell
# NB: might be better and not much harder to assume, e.g., linear variation
function update_crossing_times!(t, v, d)
    # d contains the cell width associated with
    # each of the m grid points
    n = length(d)
    # ensure that the arrays containing the crossing time for each cell (t)
    # and the speed associated with each cell (v) are inbounds
    @boundscheck n == length(t) || throw(BoundsError(t))
    @boundscheck n == length(v) || throw(BoundsError(v))
    # the crossing time for each cell is the width of the cell
    # divided by the speed of particles within the cell
    @inbounds for i ∈ 1:n
        t[i] = abs(d[i]/v[i])
    end
    return nothing
end
# follow trajectory from each grid point at time level n+1
# backwards in time until Δt has elapsed to find
# the departure points and the indices of the nearest downwind grid points
# to the departure points
# NB: have assumed positive advection speed everywhere
# NB: need to generalize
# dep: array containing the locations of the departure points
# dep_idx: array containing the indices of the nearest downwind
# grid point to the departure point
# tbound: array used to store the cumulative time spent by a particle moving along its
# characteristic backwards from the downwind boundary.  only needed if BC is periodic
# tcell: array containing the amount of time required to cross each cell
# v: the advection speed within each cell
# z: grid point locations
# dt: time step size
#function find_departure_points!(dep, dep_idx, tbound, tcell, v, coord, bc, dt)
function find_departure_points!(SL, coord, v, dt)
    # n is the number of grid points along this coordinate axis
    n = coord.n
    # ensure that all of the arrays used in this function are inbounds
    @boundscheck n == length(SL.crossing_time) || throw(BoundsError(SL.crossing_time))
    @boundscheck n == length(SL.dep_idx) || throw(BoundsError(SL.dep_idx))
    @boundscheck n == length(v) || throw(BoundsError(v))
    # if periodic boundary condition, will be most efficient to store
    # the time taken by a characteristic to pass from the downwind boundary
    # to each point on the grid, as this will be used for all characteristics
    # that wrap around from -L/2 to L/2
    #if bc == "periodic"
        #calculate_time_from_boundary!(tbound, tcell, m)
    #end
    @inbounds begin
        # obtain the departure point for all characteristics except the one
        # terminating at the upwind boundary, which is determined by the
        # zero incoming boundary condition
        SL.dep_pts[1] = coord.grid[1]
        # set the departure index to be at the upwind boundary, as the
        # characteristic will originate upwind from this
        SL.dep_idx[1] = 0
        # start with the characteristic at the furthest point downwind
        jstart = n
        # ttotal = cumulative time integrating backward along trajectory
        # should be initialized to zero to start trajectory tracing
        ttotal_in = 0.
        # sweep upwind and calculate departure points for each characteristic
        for i ∈ n:-1:2
            # calculate the departure point for the ith characteristic
            # updates dep, dep_idx, and ttotal
#        ttotal_out = departure_point!(SL.dep_pts, SL.dep_idx, ttotal_in, i,
#            jstart, SL.crossing_time, coord.grid, v, dt)
            ttotal_out = departure_point!(SL, ttotal_in, i,
                jstart, coord.grid, v, dt)
            # account for cases where departure point is less than one grid
            # spacing away from arrival point
            # jstart will be the grid point to start the time integration
            # for the i-1 characteristic (this is nearest point upwind
            # of the departure point for the ith characteristic)
            jstart = max(min(SL.dep_idx[i],i-1),2)
            # the cumulative time spent on the i-1 characteristic in integrating
            # backward from its arrival point to the grid point corresponding
            # to jstart
            ttotal_in = max(0.,ttotal_out - SL.crossing_time[i])
        end
    end
    return nothing
end
# calculate the departure point for the ith characteristic
# overwrites dep[i], dep_idx[i], and ttotal[i]
# note that the dep_idx calculated here is the index of the nearest
# downwind gridpoint to the departure point (which is in general offgrid)
#function departure_point!(dep, dep_idx, t_in, i, jstart, tcell, z, v, dt)
function departure_point!(SL, t_in, i, jstart, grid, v, dt)
    t_out = t_in
    @inbounds begin
        for j ∈ jstart:-1:2
            tmp = t_out + SL.crossing_time[j]
            if tmp >= dt
                SL.dep_pts[i] = grid[j] - v[j]*(dt-t_out)
                SL.dep_idx[i] = j
                return t_out
            else
                t_out = tmp
            end
        end
        # departure point not found before reaching upwind element boundary, so
        # set departure point to be the upwind boundary, which is given
        # by zero incoming boundary condition
        SL.dep_pts[i] = grid[1]
        # similarly, dep_idx must be set to the upwind point nearest the boundary
        # that is not itself the boundary
        SL.dep_idx[i] = 0
    end
    return t_out
end
# if periodic boundary condition, will be most efficient to store
# the time taken by a characteristic to pass from the downwind boundary
# to each point on the grid, as this will be used for all characteristics
# that wrap around from -L/2 to L/2
function calculate_time_from_boundary!(tbound, tcell, m)
    # tbound is the time spent on a characteristic in getting from
    # the downdiwnd boundary to the ith grid point
    @boundscheck m == length(tbound) || throw(BoundsError(tbound))
    @inbounds begin
        # starting at grid point m, so no time needed to get there
        tbound[m] = 0.
        # sweep upwind, calculating the integrated time out to each grid point
        for i ∈ m-1:-1:1
            idx = i+1
            tbound[i] = tbound[idx] + tcell[idx]
        end
    end
    return nothing
end
# calculate the departure point for the ith characteristic
# overwrites dep[i], dep_idx[i], and ttotal[i]
# note that the dep_idx calculated here is the index of the nearest
# downwind gridpoint to the departure point (which is in general offgrid)
function departure_point_periodic!(dep, dep_idx, total, i, jstart, tcell, z, v, dt)
    @boundscheck jstart <= length(z) || throw(BoundsError(z))
    @boundscheck jstart <= length(v) || throw(BoundsError(v))
    @boundscheck jstart <= length(tcell) || throw(BoundsError(tcell))
    @inbounds begin
        for j ∈ jstart:-1:2
            tmp = total[i] + tcell[j]
            if tmp >= dt
                dep[i] = z[j] - v[j]*(dt-total[i])
                dep_idx[i] = j
                return nothing
            else
                total[i] = tmp
            end
        end
        j = jstart
        while total[i] < dt
            tmp = total[i] + tcell[j]
            if tmp >= dt
                dep[i] = z[j] - v[j]*(dt-total[i])
                dep_idx[i] = j
                total[i] = dt
            else
                total[i] = tmp
            end
            if j == 2
                j = m
            else
                j -= 1
            end
        end


        # departure point not found before reaching upwind element boundary, so
        # set departure point to be the upwind boundary, which is given
        # by zero incoming boundary condition
        dep[i] = z[1]
        # similarly, dep_idx must be set to the upwind point nearest the boundary
        # that is not itself the boundary
        dep_idx[i] = 1
    end
    return nothing
end
# determine the nearest grid point to each departure point
#function project_characteristics_onto_grid!(dep_idx, dep, vc, z, dz, dt)
function project_characteristics_onto_grid!(SL, coord, dt)
    # n is the number of grid points along this coordinate axis
    n = coord.n
    # ensure arrays used in this function are inbounds
    @boundscheck n == length(SL.dep_idx) || throw(BoundsError(SL.dep_idx))
    @boundscheck n == length(SL.dep_pts) || throw(BoundsError(SL.dep_pts))
    @boundscheck n == length(coord.cell_width) || throw(BoundsError(coord.cell_width))
    @boundscheck n == length(SL.characteristic_speed) ||
        throw(BoundsError(SL.characteristic_speed))

    @inbounds for i ∈ 1:n
        idx = SL.dep_idx[i]
        if idx == 0
            # departure point/index already found to be upwind of upwind boundary
            # due to zero incoming boundary condition, okay to use
            # upwind boundary as departure point/index
            # this has already been set when finding departure points
            # similarly, no need to update the characteristic speed,
            # as exact speed from time level n gives a departure point
            # where the function value is the same as the upwind boundary (zero)
            # NB: need to revisit this, but setting vc to be negative
            # NB: for the moment as a way of identifying characteristics
            # NB: originating beyond the grid boundary
            SL.characteristic_speed[i] = -1.0
        else
            if coord.grid[idx]-SL.dep_pts[i] < 0.5*coord.cell_width[idx]
                # no need to do anything with dep_idx, as this is actually
                # the closest grid point to the departure point
            else
                # the nearest grid point to the departure point is upwind
                # of the departure point, so modify the dep_idx accordingly
                SL.dep_idx[i] = idx-1
            end
            # update the characteristic speed to account
            # for the trajectory slope change needed to make departure point
            # be the nearest grid point.
            # despite the fact that the spatially-dependent speed at time
            # level n was used to find the departure point, one can replace
            # this with the constant velocity along the ith characteristic
            # that was needed to arrive at the departure point
            SL.characteristic_speed[i] = (coord.grid[i]-coord.grid[SL.dep_idx[i]])/dt
        end
    end
    return nothing
end

end

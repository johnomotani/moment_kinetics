"""
Interpolation routines intended for post-processing.

Note these are not guaranteed to be highly optimized!
"""
module interpolation

export interpolate_to_grid_z

using ..type_definitions: mk_float

# Define dummy function so both chebyshev.jl and finite_differences.jl can merge new
# implementations to it.
interpolate_to_grid_1d() = nothing

function interpolate_to_grid_z(newgrid, f::Array{mk_float, 3}, z, spectral)
    size_f = size(f)
    result = Array{mk_float}(undef, (size(newgrid)[1], size_f[2:end]...))

    for is ∈ 1:size_f[3]
        for ivpa ∈ 1:size_f[2]
            result[:, ivpa, is] = interpolate_to_grid_1d(newgrid, f[:, ivpa, is], z, spectral)
        end
    end

    return result
end

function interpolate_to_grid_z(newgrid, f::Array{mk_float, 2}, z, spectral)
    size_f = size(f)
    result = Array{mk_float}(undef, (size(newgrid)[1], size_f[2]))

    for is ∈ 1:size_f[2]
        result[:, is] = interpolate_to_grid_1d(newgrid, f[:, is], z, spectral)
    end

    return result
end

function interpolate_to_grid_z(newgrid, f::Array{mk_float, 1}, z, spectral)
    return interpolate_to_grid_1d(newgrid, f, z, spectral)
end

function interpolate_to_grid_vpa(newgrid, f::Array{mk_float, 3}, vpa, spectral)
    size_f = size(f)
    result = Array{mk_float}(undef, (size_f[1], size(newgrid)[1], size_f[3]))

    for is ∈ 1:size_f[3]
        for iz ∈ 1:size_f[1]
            result[iz, :, is] = interpolate_to_grid_1d(newgrid, f[iz, :, is], vpa, spectral)
        end
    end

    return result
end

end
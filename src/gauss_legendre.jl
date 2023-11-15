"""
module for Gauss-Legendre-Lobatto and Gauss-Legendre-Radau spectral element grids
"""
module gauss_legendre

export gausslobattolegendre_differentiation_matrix!
export gaussradaulegendre_differentiation_matrix!
export GaussLegendreLobatto_mass_matrix!
export GaussLegendre_mass_matrix_1!
export GaussLegendreLobatto_inverse_mass_matrix!
export GaussLegendreLobatto_K_matrix!
export GaussLegendreLobatto_S_matrix!
export GaussLegendre_S_matrix_1!
export scaled_gauss_legendre_lobatto_grid
export scaled_gauss_legendre_radau_grid
export gausslegendre_derivative!
export gausslegendre_apply_Kmat!
export gausslegendre_apply_Lmat!
export gausslegendre_mass_matrix_solve!
export setup_gausslegendre_pseudospectral
export GaussLegendre_weak_product_matrix!
export ielement_global_func
export get_QQ_local!

using FastGaussQuadrature
using LegendrePolynomials: Pl, dnPl
using LinearAlgebra: mul!, lu, LU
using SparseArrays: sparse, AbstractSparseArray
using ..type_definitions: mk_float, mk_int
using ..array_allocation: allocate_float


"""
structs for passing around matrices for taking
the derivatives on Gauss-Legendre points in 1D
"""
struct gausslegendre_base_info{}
    # elementwise differentiation matrix (ngrid*ngrid)
    Dmat::Array{mk_float,2}
    # local mass matrix type 0
    M0::Array{mk_float,2}
    # local mass matrix type 1
    M1::Array{mk_float,2}
    # local mass matrix type 2
    M2::Array{mk_float,2}
    # local S (weak derivative) matrix type 0
    S0::Array{mk_float,2}
    # local S (weak derivative) matrix type 1
    S1::Array{mk_float,2}
    # local K (weak second derivative) matrix type 0
    K0::Array{mk_float,2}
    # local K (weak second derivative) matrix type 1
    K1::Array{mk_float,2}
    # local K (weak second derivative) matrix type 2
    K2::Array{mk_float,2}
    # local P (weak derivative no integration by parts) matrix type 0
    P0::Array{mk_float,2}
    # local P (weak derivative no integration by parts) matrix type 1
    P1::Array{mk_float,2}
    # local P (weak derivative no integration by parts) matrix type 2
    P2::Array{mk_float,2}
    # boundary condition differentiation matrix (for vperp grid using radau points)
    D0::Array{mk_float,1}
    # local nonlinear diffusion matrix Y00
    Y00::Array{mk_float,3}
    # local nonlinear diffusion matrix Y01
    Y01::Array{mk_float,3}
    # local nonlinear diffusion matrix Y10
    Y10::Array{mk_float,3}
    # local nonlinear diffusion matrix Y11
    Y11::Array{mk_float,3}
    # local nonlinear diffusion matrix Y20
    Y20::Array{mk_float,3}
    # local nonlinear diffusion matrix Y21
    Y21::Array{mk_float,3}
    # local nonlinear diffusion matrix Y30
    Y30::Array{mk_float,3}
    # local nonlinear diffusion matrix Y31
    Y31::Array{mk_float,3}
end

struct gausslegendre_info{}
    lobatto::gausslegendre_base_info
    radau::gausslegendre_base_info
    # global (1D) mass matrix
    mass_matrix::Array{mk_float,2}
    # global (1D) weak derivative matrix
    #S_matrix::Array{mk_float,2}
    S_matrix::AbstractSparseArray{mk_float,Ti,2} where Ti
    # global (1D) weak second derivative matrix
    K_matrix::Array{mk_float,2}
    # global (1D) weak Laplacian derivative matrix
    L_matrix::Array{mk_float,2}
    # global (1D) LU object
    mass_matrix_lu::T where T
    # dummy matrix for local operators
    Qmat::Array{mk_float,2}
end

function setup_gausslegendre_pseudospectral(coord)
    lobatto = setup_gausslegendre_pseudospectral_lobatto(coord)
    radau = setup_gausslegendre_pseudospectral_radau(coord)
    mass_matrix = allocate_float(coord.n,coord.n)
    S_matrix = allocate_float(coord.n,coord.n)
    K_matrix = allocate_float(coord.n,coord.n)
    L_matrix = allocate_float(coord.n,coord.n)
    
    setup_global_weak_form_matrix!(mass_matrix, lobatto, radau, coord, "M")
    setup_global_weak_form_matrix!(S_matrix, lobatto, radau, coord, "S")
    setup_global_weak_form_matrix!(K_matrix, lobatto, radau, coord, "K_with_BC_terms")
    setup_global_weak_form_matrix!(L_matrix, lobatto, radau, coord, "L_with_BC_terms")
    mass_matrix_lu = lu(sparse(mass_matrix))
    Qmat = allocate_float(coord.ngrid,coord.ngrid)
    return gausslegendre_info(lobatto,radau,mass_matrix,sparse(S_matrix),K_matrix,L_matrix,mass_matrix_lu,Qmat)
end

function setup_gausslegendre_pseudospectral_lobatto(coord)
    x, w = gausslobatto(coord.ngrid)
    Dmat = allocate_float(coord.ngrid, coord.ngrid)
    gausslobattolegendre_differentiation_matrix!(Dmat,x,coord.ngrid)
    
    M0 = allocate_float(coord.ngrid, coord.ngrid)
    GaussLegendre_weak_product_matrix!(M0,coord.ngrid,x,w,"M0")
    M1 = allocate_float(coord.ngrid, coord.ngrid)
    GaussLegendre_weak_product_matrix!(M1,coord.ngrid,x,w,"M1")
    M2 = allocate_float(coord.ngrid, coord.ngrid)
    GaussLegendre_weak_product_matrix!(M2,coord.ngrid,x,w,"M2")
    S0 = allocate_float(coord.ngrid, coord.ngrid)
    GaussLegendre_weak_product_matrix!(S0,coord.ngrid,x,w,"S0")
    S1 = allocate_float(coord.ngrid, coord.ngrid)
    GaussLegendre_weak_product_matrix!(S1,coord.ngrid,x,w,"S1")
    K0 = allocate_float(coord.ngrid, coord.ngrid)
    GaussLegendre_weak_product_matrix!(K0,coord.ngrid,x,w,"K0")
    K1 = allocate_float(coord.ngrid, coord.ngrid)
    GaussLegendre_weak_product_matrix!(K1,coord.ngrid,x,w,"K1")
    K2 = allocate_float(coord.ngrid, coord.ngrid)
    GaussLegendre_weak_product_matrix!(K2,coord.ngrid,x,w,"K2")
    P0 = allocate_float(coord.ngrid, coord.ngrid)
    GaussLegendre_weak_product_matrix!(P0,coord.ngrid,x,w,"P0")
    P1 = allocate_float(coord.ngrid, coord.ngrid)
    GaussLegendre_weak_product_matrix!(P1,coord.ngrid,x,w,"P1")
    P2 = allocate_float(coord.ngrid, coord.ngrid)
    GaussLegendre_weak_product_matrix!(P2,coord.ngrid,x,w,"P2")
    D0 = allocate_float(coord.ngrid)
    #@. D0 = Dmat[1,:] # values at lower extreme of element
    GaussLegendre_derivative_vector!(D0,-1.0,coord.ngrid,x,w)
    Y00 = allocate_float(coord.ngrid, coord.ngrid, coord.ngrid)
    GaussLegendre_weak_product_matrix!(Y00,coord.ngrid,x,w,"Y00")
    Y01 = allocate_float(coord.ngrid, coord.ngrid, coord.ngrid)
    GaussLegendre_weak_product_matrix!(Y01,coord.ngrid,x,w,"Y01")
    Y10 = allocate_float(coord.ngrid, coord.ngrid, coord.ngrid)
    GaussLegendre_weak_product_matrix!(Y10,coord.ngrid,x,w,"Y10")
    Y11 = allocate_float(coord.ngrid, coord.ngrid, coord.ngrid)
    GaussLegendre_weak_product_matrix!(Y11,coord.ngrid,x,w,"Y11")
    Y20 = allocate_float(coord.ngrid, coord.ngrid, coord.ngrid)
    GaussLegendre_weak_product_matrix!(Y20,coord.ngrid,x,w,"Y20")
    Y21 = allocate_float(coord.ngrid, coord.ngrid, coord.ngrid)
    GaussLegendre_weak_product_matrix!(Y21,coord.ngrid,x,w,"Y21")
    Y30 = allocate_float(coord.ngrid, coord.ngrid, coord.ngrid)
    GaussLegendre_weak_product_matrix!(Y30,coord.ngrid,x,w,"Y30")
    Y31 = allocate_float(coord.ngrid, coord.ngrid, coord.ngrid)
    GaussLegendre_weak_product_matrix!(Y31,coord.ngrid,x,w,"Y31")
    
    return gausslegendre_base_info(Dmat,M0,M1,M2,S0,S1,
            K0,K1,K2,P0,P1,P2,D0,Y00,Y01,Y10,Y11,Y20,Y21,Y30,Y31)
end

function setup_gausslegendre_pseudospectral_radau(coord)
    # Gauss-Radau points on [-1,1)
    x, w = gaussradau(coord.ngrid)
    # Gauss-Radau points on (-1,1] 
    xreverse, wreverse = -reverse(x), reverse(w)
    # elemental differentiation matrix
    Dmat = allocate_float(coord.ngrid, coord.ngrid)
    gaussradaulegendre_differentiation_matrix!(Dmat,x,coord.ngrid)
    
    M0 = allocate_float(coord.ngrid, coord.ngrid)
    GaussLegendre_weak_product_matrix!(M0,coord.ngrid,xreverse,wreverse,"M0",radau=true)
    M1 = allocate_float(coord.ngrid, coord.ngrid)
    GaussLegendre_weak_product_matrix!(M1,coord.ngrid,xreverse,wreverse,"M1",radau=true)
    M2 = allocate_float(coord.ngrid, coord.ngrid)
    GaussLegendre_weak_product_matrix!(M2,coord.ngrid,xreverse,wreverse,"M2",radau=true)
    S0 = allocate_float(coord.ngrid, coord.ngrid)
    GaussLegendre_weak_product_matrix!(S0,coord.ngrid,xreverse,wreverse,"S0",radau=true)
    S1 = allocate_float(coord.ngrid, coord.ngrid)
    GaussLegendre_weak_product_matrix!(S1,coord.ngrid,xreverse,wreverse,"S1",radau=true)
    K0 = allocate_float(coord.ngrid, coord.ngrid)
    GaussLegendre_weak_product_matrix!(K0,coord.ngrid,xreverse,wreverse,"K0",radau=true)
    K1 = allocate_float(coord.ngrid, coord.ngrid)
    GaussLegendre_weak_product_matrix!(K1,coord.ngrid,xreverse,wreverse,"K1",radau=true)
    K2 = allocate_float(coord.ngrid, coord.ngrid)
    GaussLegendre_weak_product_matrix!(K2,coord.ngrid,xreverse,wreverse,"K2",radau=true)
    P0 = allocate_float(coord.ngrid, coord.ngrid)
    GaussLegendre_weak_product_matrix!(P0,coord.ngrid,xreverse,wreverse,"P0",radau=true)
    P1 = allocate_float(coord.ngrid, coord.ngrid)
    GaussLegendre_weak_product_matrix!(P1,coord.ngrid,xreverse,wreverse,"P1",radau=true)
    P2 = allocate_float(coord.ngrid, coord.ngrid)
    GaussLegendre_weak_product_matrix!(P2,coord.ngrid,xreverse,wreverse,"P2",radau=true)
    D0 = allocate_float(coord.ngrid)
    GaussLegendre_derivative_vector!(D0,-1.0,coord.ngrid,xreverse,wreverse,radau=true)
    Y00 = allocate_float(coord.ngrid, coord.ngrid, coord.ngrid)
    GaussLegendre_weak_product_matrix!(Y00,coord.ngrid,xreverse,wreverse,"Y00",radau=true)
    Y01 = allocate_float(coord.ngrid, coord.ngrid, coord.ngrid)
    GaussLegendre_weak_product_matrix!(Y01,coord.ngrid,xreverse,wreverse,"Y01",radau=true)
    Y10 = allocate_float(coord.ngrid, coord.ngrid, coord.ngrid)
    GaussLegendre_weak_product_matrix!(Y10,coord.ngrid,xreverse,wreverse,"Y10",radau=true)
    Y11 = allocate_float(coord.ngrid, coord.ngrid, coord.ngrid)
    GaussLegendre_weak_product_matrix!(Y11,coord.ngrid,xreverse,wreverse,"Y11",radau=true)
    Y20 = allocate_float(coord.ngrid, coord.ngrid, coord.ngrid)
    GaussLegendre_weak_product_matrix!(Y20,coord.ngrid,xreverse,wreverse,"Y20",radau=true)
    Y21 = allocate_float(coord.ngrid, coord.ngrid, coord.ngrid)
    GaussLegendre_weak_product_matrix!(Y21,coord.ngrid,xreverse,wreverse,"Y21",radau=true)
    Y30 = allocate_float(coord.ngrid, coord.ngrid, coord.ngrid)
    GaussLegendre_weak_product_matrix!(Y30,coord.ngrid,xreverse,wreverse,"Y30",radau=true)
    Y31 = allocate_float(coord.ngrid, coord.ngrid, coord.ngrid)
    GaussLegendre_weak_product_matrix!(Y31,coord.ngrid,xreverse,wreverse,"Y31",radau=true)
    return gausslegendre_base_info(Dmat,M0,M1,M2,S0,S1,
            K0,K1,K2,P0,P1,P2,D0,Y00,Y01,Y10,Y11,Y20,Y21,Y30,Y31)
end 
"""
function for taking the first derivative on Gauss-Legendre points
"""
function gausslegendre_derivative!(df, ff, gausslegendre, coord)
    # define local variable nelement for convenience
    nelement = coord.nelement_local
    # check array bounds
    @boundscheck nelement == size(df,2) && coord.ngrid == size(df,1) || throw(BoundsError(df))
    
    # variable k will be used to avoid double counting of overlapping point
    k = 0
    j = 1 # the first element
    imin = coord.imin[j]-k
    # imax is the maximum index on the full grid for this (jth) element
    imax = coord.imax[j]        
    if coord.name == "vperp" && coord.irank == 0 # differentiate this element with the Radau scheme
        @views mul!(df[:,j],gausslegendre.radau.Dmat[:,:],ff[imin:imax])
    else #differentiate using the Lobatto scheme
        @views mul!(df[:,j],gausslegendre.lobatto.Dmat[:,:],ff[imin:imax])
    end
    # transform back to the physical coordinate scale
    for i in 1:coord.ngrid
        df[i,j] /= coord.element_scale[j]
    end
    # calculate the derivative on each element
    @inbounds for j ∈ 2:nelement
        k = 1 
        imin = coord.imin[j]-k
        # imax is the maximum index on the full grid for this (jth) element
        imax = coord.imax[j]
        @views mul!(df[:,j],gausslegendre.lobatto.Dmat[:,:],ff[imin:imax])        
        # transform back to the physical coordinate scale
        for i in 1:coord.ngrid
            df[i,j] /= coord.element_scale[j]
        end
    end

    return nothing
end

"""
function for taking the weak-form second derivative on Gauss-Legendre points
"""
function gausslegendre_apply_Kmat!(df, ff, gausslegendre, coord)
    # define local variable nelement for convenience
    nelement = coord.nelement_local
    # check array bounds
    @boundscheck nelement == size(df,2) && coord.ngrid == size(df,1) || throw(BoundsError(df))
    
    # variable k will be used to avoid double counting of overlapping point
    k = 0
    j = 1 # the first element
    imin = coord.imin[j]-k
    # imax is the maximum index on the full grid for this (jth) element
    imax = coord.imax[j]        
    get_KK_local!(gausslegendre.Qmat,j,gausslegendre.lobatto,gausslegendre.radau,coord,explicit_BC_terms=true)
    #println(gausslegendre.Qmat)
    @views mul!(df[:,j],gausslegendre.Qmat[:,:],ff[imin:imax])
    zero_gradient_bc_lower_boundary = false#true
    if coord.name == "vperp" && zero_gradient_bc_lower_boundary
       # set the 1st point of the RHS vector to zero 
       # consistent with use with the mass matrix with D f = 0 boundary conditions
       df[1,j] = 0.0
    end
    # calculate the derivative on each element
    @inbounds for j ∈ 2:nelement
        k = 1 
        imin = coord.imin[j]-k
        # imax is the maximum index on the full grid for this (jth) element
        imax = coord.imax[j]
        #@views mul!(df[:,j],gausslegendre.lobatto.Kmat[:,:],ff[imin:imax])
        get_KK_local!(gausslegendre.Qmat,j,gausslegendre.lobatto,gausslegendre.radau,coord,explicit_BC_terms=true)
        #println(gausslegendre.Qmat)
        @views mul!(df[:,j],gausslegendre.Qmat[:,:],ff[imin:imax])
    end
    #for j in 1:nelement
    #    println(df[:,j])
    #end
    return nothing
end

"""
function for taking the weak-form Laplacian derivative on Gauss-Legendre points
"""
function gausslegendre_apply_Lmat!(df, ff, gausslegendre, coord)
    # define local variable nelement for convenience
    nelement = coord.nelement_local
    # check array bounds
    @boundscheck nelement == size(df,2) && coord.ngrid == size(df,1) || throw(BoundsError(df))
    
    # variable k will be used to avoid double counting of overlapping point
    k = 0
    j = 1 # the first element
    imin = coord.imin[j]-k
    # imax is the maximum index on the full grid for this (jth) element
    imax = coord.imax[j]        
    get_LL_local!(gausslegendre.Qmat,j,gausslegendre.lobatto,gausslegendre.radau,coord,explicit_BC_terms=true)
    #println(gausslegendre.Qmat)
    @views mul!(df[:,j],gausslegendre.Qmat[:,:],ff[imin:imax])
    zero_gradient_bc_lower_boundary = false#true
    if coord.name == "vperp" && zero_gradient_bc_lower_boundary
       # set the 1st point of the RHS vector to zero 
       # consistent with use with the mass matrix with D f = 0 boundary conditions
       df[1,j] = 0.0
    end
    # calculate the derivative on each element
    @inbounds for j ∈ 2:nelement
        k = 1 
        imin = coord.imin[j]-k
        # imax is the maximum index on the full grid for this (jth) element
        imax = coord.imax[j]
        #@views mul!(df[:,j],gausslegendre.lobatto.Kmat[:,:],ff[imin:imax])
        get_LL_local!(gausslegendre.Qmat,j,gausslegendre.lobatto,gausslegendre.radau,coord,explicit_BC_terms=true)
        #println(gausslegendre.Qmat)
        @views mul!(df[:,j],gausslegendre.Qmat[:,:],ff[imin:imax])
    end
    #for j in 1:nelement
    #    println(df[:,j])
    #end
    return nothing
end

function gausslegendre_mass_matrix_solve!(f,b,spectral)
    # invert mass matrix system
    y = spectral.mass_matrix_lu \ b
    @. f = y
    return nothing
end

"""
Formula for differentiation matrix taken from p196 of Chpt `The Spectral Elemtent Method' of 
`Computational Seismology'. Heiner Igel First Edition. Published in 2017 by Oxford University Press.
Or https://doc.nektar.info/tutorials/latest/fundamentals/differentiation/fundamentals-differentiationch2.html

D -- differentiation matrix 
x -- Gauss-Legendre-Lobatto points in [-1,1]
ngrid -- number of points per element (incl. boundary points)

Note that D has does not include a scaling factor
"""
function gausslobattolegendre_differentiation_matrix!(D::Array{Float64,2},x::Array{Float64,1},ngrid::Int64)
    D[:,:] .= 0.0
    for ix in 1:ngrid
        for ixp in 1:ngrid
            if !(ix == ixp)
                D[ix,ixp] = (Pl(x[ix],ngrid-1)/Pl(x[ixp],ngrid-1))/(x[ix]-x[ixp])
            end
        end
    end
    # uncomment for analytical diagonal values 
    #D[1,1] = -0.25*(ngrid - 1)*ngrid
    #D[ngrid,ngrid] = 0.25*(ngrid - 1)*ngrid
    #for ix in 1:ngrid-1
    #   D[ix,ix] = 0.0
    #end
    # get diagonal values from sum of nonzero off diagonal values 
    for ix in 1:ngrid
        D[ix,ix] = -sum(D[ix,:])
    end 
    return nothing
end
"""
From 
https://doc.nektar.info/tutorials/latest/fundamentals/differentiation/fundamentals-differentiationch2.html

D -- differentiation matrix 
x -- Gauss-Legendre-Radau points in [-1,1)
ngrid -- number of points per element (incl. boundary points)

Note that D has does not include a scaling factor
"""
function gaussradaulegendre_differentiation_matrix!(D::Array{Float64,2},x::Array{Float64,1},ngrid::Int64)
    D[:,:] .= 0.0
    for ix in 1:ngrid
        for ixp in 1:ngrid
            if !(ix == ixp)
                D[ix,ixp] = (Pl(x[ix],ngrid-1)/Pl(x[ixp],ngrid-1))*((1.0 - x[ixp])/(1.0 - x[ix]))/(x[ix]-x[ixp])
            end
        end
    end
    # uncomment for analytical diagonal values 
    #D[1,1] = -0.25*(ngrid - 1)*(ngrid + 1)
    #for ix in 2:ngrid
    #   D[ix,ix] = 0.5/(1.0 - x[ix])
    #end
    # get diagonal values from sum of nonzero off diagonal values 
    for ix in 1:ngrid
        D[ix,ix] = -sum(D[ix,:])
    end
    
    # get into correct order for a grid on (-1,1]
    Dreverse = copy(D)
    for ix in 1:ngrid
        for ixp in 1:ngrid
            Dreverse[ngrid-ix+1,ngrid-ixp+1] = -D[ix,ixp]
        end
    end
    D .= Dreverse
    return nothing
end

"""
Gauss-Legendre derivative at arbitrary x values, for boundary condition on radau points
D0 -- the vector
xj -- the x location where the derivative is evaluated 
ngrid -- number of points in x
x -- the grid from -1, 1
Note that D0 is not scaled to the physical grid
"""
function GaussLegendre_derivative_vector!(D0,xj,ngrid,x,wgts;radau=false)
    # coefficient in expansion of 
    # lagrange polys in terms of Legendre polys
    gamma = allocate_float(ngrid)
    for i in 1:ngrid-1
        gamma[i] = Legendre_h_n(i-1)
    end
    if radau
        gamma[ngrid] = Legendre_h_n(ngrid-1)
    else
        gamma[ngrid] = 2.0/(ngrid - 1)
    end
    
    @. D0 = 0.0
    for i in 1:ngrid
        for k in 1:ngrid
            D0[i] += wgts[i]*Pl(x[i],k-1)*dnPl(xj,k-1,1)/gamma[k]
        end
    end
    # set `diagonal' value
    D0[1] = 0.0
    D0[1] = -sum(D0[:])
    #@. D0 *= 2.0*float(nelement_global)/L
end

"""
result of the inner product of Legendre polys of order k
"""
function Legendre_h_n(k)
    h_n = 2.0/(2.0*k + 1)
    return h_n
end 


"""
assign abitrary weak inner product matrix Q on a 1D line with Jacobian = 1
matrix Q acts on a single vector x such that y = Q * x is also a vector
"""
function GaussLegendre_weak_product_matrix!(QQ::Array{mk_float,2},ngrid,x,wgts,option;radau=false)
    # coefficient in expansion of 
    # lagrange polys in terms of Legendre polys
    gamma = allocate_float(ngrid)
    for i in 1:ngrid-1
        gamma[i] = Legendre_h_n(i-1)
    end
    if radau
        gamma[ngrid] = Legendre_h_n(ngrid-1)
    else
        gamma[ngrid] = 2.0/(ngrid - 1)
    end
    # appropriate inner product of Legendre polys
    # definition depends on required matrix 
    # for M0: AA = < P_i P_j >
    # for M1: AA = < P_i P_j x >
    # for M2: AA = < P_i P_j x^2 >
    # for S0: AA = -< P'_i P_j >
    # for S1: AA = -< P'_i P_j x >
    # for K0: AA = -< P'_i P'_j >
    # for K1: AA = -< P'_i P'_j x >
    # for K2: AA = -< P'_i P'_j x^2 >
    # for P0: AA = < P_i P'_j >
    # for P1: AA = < P_i P'_j x >
    # for P2: AA = < P_i P'_j x^2 >
    AA = allocate_float(ngrid,ngrid)
    nquad = 2*ngrid
    zz, wz = gausslegendre(nquad)
    @. AA = 0.0
    if option == "M0"
        for j in 1:ngrid
            for i in 1:ngrid
                for k in 1:nquad
                    AA[i,j] += wz[k]*Pl(zz[k],i-1)*Pl(zz[k],j-1)
                end
            end
        end
    elseif option == "M1"
        for j in 1:ngrid
            for i in 1:ngrid
                for k in 1:nquad
                    AA[i,j] += zz[k]*wz[k]*Pl(zz[k],i-1)*Pl(zz[k],j-1)
                end
            end
        end
    elseif option == "M2"
        for j in 1:ngrid
            for i in 1:ngrid
                for k in 1:nquad
                    AA[i,j] += (zz[k]^2)*wz[k]*Pl(zz[k],i-1)*Pl(zz[k],j-1)
                end
            end
        end
    elseif option == "S0"
        for j in 1:ngrid
            for i in 1:ngrid
                for k in 1:nquad
                    AA[i,j] -= wz[k]*dnPl(zz[k],i-1,1)*Pl(zz[k],j-1)
                end
            end
        end
    elseif option == "S1"
        for j in 1:ngrid
            for i in 1:ngrid
                for k in 1:nquad
                    AA[i,j] -= zz[k]*wz[k]*dnPl(zz[k],i-1,1)*Pl(zz[k],j-1)
                end
            end
        end
    elseif option == "K0"
        for j in 1:ngrid
            for i in 1:ngrid
                for k in 1:nquad
                    AA[i,j] -= wz[k]*dnPl(zz[k],i-1,1)*dnPl(zz[k],j-1,1)
                end
            end
        end
    elseif option == "K1"
        for j in 1:ngrid
            for i in 1:ngrid
                for k in 1:nquad
                    AA[i,j] -= zz[k]*wz[k]*dnPl(zz[k],i-1,1)*dnPl(zz[k],j-1,1)
                end
            end
        end
    elseif option == "K2"
        for j in 1:ngrid
            for i in 1:ngrid
                for k in 1:nquad
                    AA[i,j] -= (zz[k]^2)*wz[k]*dnPl(zz[k],i-1,1)*dnPl(zz[k],j-1,1)
                end
            end
        end
    elseif option == "P0"
        for j in 1:ngrid
            for i in 1:ngrid
                for k in 1:nquad
                    AA[i,j] += wz[k]*Pl(zz[k],i-1)*dnPl(zz[k],j-1,1)
                end
            end
        end
    elseif option == "P1"
        for j in 1:ngrid
            for i in 1:ngrid
                for k in 1:nquad
                    AA[i,j] += zz[k]*wz[k]*Pl(zz[k],i-1)*dnPl(zz[k],j-1,1)
                end
            end
        end
    elseif option == "P2"
        for j in 1:ngrid
            for i in 1:ngrid
                for k in 1:nquad
                    AA[i,j] += (zz[k]^2)*wz[k]*Pl(zz[k],i-1)*dnPl(zz[k],j-1,1)
                end
            end
        end
    end
    
    QQ .= 0.0
    for j in 1:ngrid
        for i in 1:ngrid
            for l in 1:ngrid
                for k in 1:ngrid
                    QQ[i,j] += wgts[i]*wgts[j]*Pl(x[i],k-1)*Pl(x[j],l-1)*AA[k,l]/(gamma[k]*gamma[l])
                end
            end
        end
    end
    return nothing
end

"""
assign abitrary weak inner product matrix Q on a 1D line with Jacobian = 1
matrix Q acts on two vectors x1 and x2 such that the quadratic form 
y = x1 * Q * x2 is also a vector
"""
function GaussLegendre_weak_product_matrix!(QQ::Array{mk_float,3},ngrid,x,wgts,option;radau=false)
    # coefficient in expansion of 
    # lagrange polys in terms of Legendre polys
    gamma = allocate_float(ngrid)
    for i in 1:ngrid-1
        gamma[i] = Legendre_h_n(i-1)
    end
    if radau
        gamma[ngrid] = Legendre_h_n(ngrid-1)
    else
        gamma[ngrid] = 2.0/(ngrid - 1)
    end
    # appropriate inner product of Legendre polys
    # definition depends on required matrix 
    # for Y00: AA = < P_i P_j P_k >
    # for Y01: AA = < P_i P_j P_k x >
    # for Y10: AA = < P_i P_j P'_k >
    # for Y11: AA = < P_i P_j P'_k x >
    # for Y20: AA = < P_i P'_j P'_k >
    # for Y21: AA = < P_i P'_j P'_k x >
    # for Y31: AA = < P_i P'_j P_k x >
    # for Y30: AA = < P_i P'_j P_k >
    AA = allocate_float(ngrid,ngrid,ngrid)
    nquad = 2*ngrid
    zz, wz = gausslegendre(nquad)
    @. AA = 0.0
    if option == "Y00"
        for k in 1:ngrid
            for j in 1:ngrid
                for i in 1:ngrid
                    for q in 1:nquad
                        AA[i,j,k] += wz[q]*Pl(zz[q],i-1)*Pl(zz[q],j-1)*Pl(zz[q],k-1)
                    end
                end
            end
        end
    elseif option == "Y01"
        for k in 1:ngrid
            for j in 1:ngrid
                for i in 1:ngrid
                    for q in 1:nquad
                        AA[i,j,k] += zz[q]*wz[q]*Pl(zz[q],i-1)*Pl(zz[q],j-1)*Pl(zz[q],k-1)
                    end
                end
            end
        end
    elseif option == "Y10"
        for k in 1:ngrid
            for j in 1:ngrid
                for i in 1:ngrid
                    for q in 1:nquad
                        AA[i,j,k] += wz[q]*Pl(zz[q],i-1)*Pl(zz[q],j-1)*dnPl(zz[q],k-1,1)
                    end
                end
            end
        end
    elseif option == "Y11"
        for k in 1:ngrid
            for j in 1:ngrid
                for i in 1:ngrid
                    for q in 1:nquad
                        AA[i,j,k] += zz[q]*wz[q]*Pl(zz[q],i-1)*Pl(zz[q],j-1)*dnPl(zz[q],k-1,1)
                    end
                end
            end
        end
    elseif option == "Y20"
        for k in 1:ngrid
            for j in 1:ngrid
                for i in 1:ngrid
                    for q in 1:nquad
                        AA[i,j,k] += wz[q]*Pl(zz[q],i-1)*dnPl(zz[q],j-1,1)*dnPl(zz[q],k-1,1)
                    end
                end
            end
        end
    elseif option == "Y21"
        for k in 1:ngrid
            for j in 1:ngrid
                for i in 1:ngrid
                    for q in 1:nquad
                        AA[i,j,k] += zz[q]*wz[q]*Pl(zz[q],i-1)*dnPl(zz[q],j-1,1)*dnPl(zz[q],k-1,1)
                    end
                end
            end
        end
    elseif option == "Y31"
        for k in 1:ngrid
            for j in 1:ngrid
                for i in 1:ngrid
                    for q in 1:nquad
                        AA[i,j,k] += zz[q]*wz[q]*Pl(zz[q],i-1)*dnPl(zz[q],j-1,1)*Pl(zz[q],k-1)
                    end
                end
            end
        end
    elseif option == "Y30"
        for k in 1:ngrid
            for j in 1:ngrid
                for i in 1:ngrid
                    for q in 1:nquad
                        AA[i,j,k] += wz[q]*Pl(zz[q],i-1)*dnPl(zz[q],j-1,1)*Pl(zz[q],k-1)
                    end
                end
            end
        end
    end
    
    QQ .= 0.0
    for k in 1:ngrid
        for j in 1:ngrid
            for i in 1:ngrid
                for l in 1:ngrid
                    for m in 1:ngrid
                        for n in 1:ngrid
                            QQ[i,j,k] += wgts[i]*wgts[j]*wgts[k]*Pl(x[i],n-1)*Pl(x[j],m-1)*Pl(x[k],l-1)*AA[n,m,l]/(gamma[n]*gamma[m]*gamma[l])
                        end
                    end
                end
            end
        end
    end
    return nothing
end

function scale_factor_func(L,nelement_global)
    return 0.5*L/float(nelement_global)
end

function shift_factor_func(L,nelement_global,nelement_local,irank,ielement_local)
    #ielement_global = ielement_local # for testing + irank*nelement_local
    ielement_global = ielement_local + irank*nelement_local # proper line for future distributed memory MPI use
    shift = L*((float(ielement_global)-0.5)/float(nelement_global) - 0.5)
    return shift
end

function ielement_global_func(nelement_local,irank,ielement_local)
    return ielement_global = ielement_local + irank*nelement_local
end

"""
function for setting up the full Gauss-Legendre-Lobatto
grid and collocation point weights
"""
function scaled_gauss_legendre_lobatto_grid(ngrid, nelement_local, n_local, element_scale, element_shift, imin, imax)
    # get Gauss-Legendre-Lobatto points and weights on [-1,1]
    x, w = gausslobatto(ngrid)
    # grid and weights arrays
    grid = allocate_float(n_local)
    wgts = allocate_float(n_local)
    wgts .= 0.0
    #integer to deal with the overlap of element boundaries
    k = 1
    @inbounds for j in 1:nelement_local
        # element_scale[j]
        # element_shift[j]
        # factor with maps [-1,1] -> a subset of [-L/2, L/2]
        @. grid[imin[j]:imax[j]] = element_scale[j]*x[k:ngrid] + element_shift[j]
        
        # calculate the weights
        # remembering on boundary points to include weights
        # from both left and right elements
        #println(imin[j]," ",imax[j])
        @. wgts[imin[j] - k + 1:imax[j]] += element_scale[j]*w[1:ngrid] 
        
        k = 2        
    end
    return grid, wgts
end

"""
function for setting up the full Gauss-Legendre-Radau
grid and collocation point weights
see comments of Gauss-Legendre-Lobatto routine above
"""
function scaled_gauss_legendre_radau_grid(ngrid, nelement_local, n_local, element_scale, element_shift, imin, imax, irank)
    # get Gauss-Legendre-Lobatto points and weights on [-1,1]
    x_lob, w_lob = gausslobatto(ngrid)
    # get Gauss-Legendre-Radau points and weights on [-1,1)
    x_rad, w_rad = gaussradau(ngrid)
    # transform to a Gauss-Legendre-Radau grid on (-1,1]
    x_rad, w_rad = -reverse(x_rad), reverse(w_rad)#
    # grid and weights arrays
    grid = allocate_float(n_local)
    wgts = allocate_float(n_local)
    wgts .= 0.0
    if irank == 0
        # for 1st element, fill in with Gauss-Legendre-Radau points
        j = 1
        # element_scale[j]
        # element_shift[j]
        # factor with maps [-1,1] -> a subset of [-L/2, L/2]
        @. grid[imin[j]:imax[j]] = element_scale[j]*x_rad[1:ngrid] + element_shift[j]
        @. wgts[imin[j]:imax[j]] += element_scale[j]*w_rad[1:ngrid]       
        #integer to deal with the overlap of element boundaries
        k = 2
        @inbounds for j in 2:nelement_local
            # element_scale[j]
            # element_shift[j]
            # factor with maps [-1,1] -> a subset of [-L/2, L/2]
            @. grid[imin[j]:imax[j]] = element_scale[j]*x_lob[k:ngrid] + element_shift[j]
            @. wgts[imin[j] - k + 1:imax[j]] += element_scale[j]*w_lob[1:ngrid]         
        end
    else # all elements are Gauss-Legendre-Lobatto
        #integer to deal with the overlap of element boundaries
        k = 1
        @inbounds for j in 1:nelement_local
            # element_scale[j]
            # element_shift[j]
            # factor with maps [-1,1] -> a subset of [-L/2, L/2]
            @. grid[imin[j]:imax[j]] = element_scale[j]*x_lob[k:ngrid] + element_shift[j]
            @. wgts[imin[j] - k + 1:imax[j]] += element_scale[j]*w_lob[1:ngrid]            
            k = 2 
        end
    end
    return grid, wgts
end

"""
function that assigns the local weak-form matrices to 
a global array QQ_global for later solving weak form of required
1D equation

option choosing type of matrix to be constructed -- "M" (mass matrix), "S" (derivative matrix)
"""
function setup_global_weak_form_matrix!(QQ_global::Array{mk_float,2},
                               lobatto::gausslegendre_base_info,
                               radau::gausslegendre_base_info, 
                               coord,option)
    QQ_j = allocate_float(coord.ngrid,coord.ngrid)
    QQ_jp1 = allocate_float(coord.ngrid,coord.ngrid)
    
    ngrid = coord.ngrid
    imin = coord.imin
    imax = coord.imax
    @. QQ_global = 0.0
    mass_matrix = (option == "M") && false
    if coord.name == "vperp"
        zero_bc_upper_boundary = true && mass_matrix
        zero_bc_lower_boundary = false && mass_matrix
        zero_gradient_bc_lower_boundary = false && mass_matrix
    else 
        zero_bc_upper_boundary = (coord.bc == "zero" || coord.bc == "zero_upper") && mass_matrix
        zero_bc_lower_boundary = (coord.bc == "zero" || coord.bc == "zero_lower")  && mass_matrix
        zero_gradient_bc_lower_boundary = false  && mass_matrix
    end
    # fill in first element 
    j = 1
    # N.B. QQ varies with ielement for vperp, but not vpa
    get_QQ_local!(QQ_j,j,lobatto,radau,coord,option)
    
    if zero_bc_lower_boundary #x.bc == "zero"
        QQ_global[imin[j],imin[j]:imax[j]] .= 0.0
        QQ_global[imin[j],imin[j]] = 1.0
    elseif zero_gradient_bc_lower_boundary
            QQ_global[imin[j],imin[j]:imax[j]] .= radau.D0[:]
    else 
        QQ_global[imin[j],imin[j]:imax[j]] .+= QQ_j[1,:]
    end
    for k in 2:imax[j]-imin[j] 
        QQ_global[k,imin[j]:imax[j]] .+= QQ_j[k,:]
    end
    if zero_bc_upper_boundary && coord.nelement_local == 1
        QQ_global[imax[j],imin[j]:imax[j]] .= 0.0
        QQ_global[imax[j],imax[j]] = 1.0
    elseif coord.nelement_local > 1 #x.bc == "zero"
        QQ_global[imax[j],imin[j]:imax[j]] .+= QQ_j[ngrid,:]./2.0
    else
        QQ_global[imax[j],imin[j]:imax[j]] .+= QQ_j[ngrid,:]
    end 
    # remaining elements recalling definitions of imax and imin
    for j in 2:coord.nelement_local
        get_QQ_local!(QQ_j,j,lobatto,radau,coord,option)
        
        #lower boundary condition on element
        QQ_global[imin[j]-1,imin[j]-1:imax[j]] .+= QQ_j[1,:]./2.0
        for k in 2:imax[j]-imin[j]+1 
            QQ_global[k+imin[j]-2,imin[j]-1:imax[j]] .+= QQ_j[k,:]
        end
        # upper boundary condition on element 
        if j == coord.nelement_local && !(zero_bc_upper_boundary)
            QQ_global[imax[j],imin[j]-1:imax[j]] .+= QQ_j[ngrid,:]
        elseif j == coord.nelement_local && zero_bc_upper_boundary
            QQ_global[imax[j],imin[j]-1:imax[j]] .= 0.0 #contributions from this element/2
            QQ_global[imax[j],imax[j]] = 1.0
        else 
            QQ_global[imax[j],imin[j]-1:imax[j]] .+= QQ_j[ngrid,:]./2.0
        end
    end
        
    return nothing
end

function get_QQ_local!(QQ::Array{mk_float,2},ielement,
        lobatto::gausslegendre_base_info,
        radau::gausslegendre_base_info, 
        coord,option)
  
        if option == "M"
            get_MM_local!(QQ,ielement,lobatto,radau,coord)
        elseif option == "R"
            get_MR_local!(QQ,ielement,lobatto,radau,coord)
        elseif option == "N"
            get_MN_local!(QQ,ielement,lobatto,radau,coord)
        elseif option == "P"
            get_PP_local!(QQ,ielement,lobatto,radau,coord)
        elseif option == "U"
            get_PU_local!(QQ,ielement,lobatto,radau,coord)
        elseif option == "S"
            get_SS_local!(QQ,ielement,lobatto,radau,coord)
        elseif option == "K"
            get_KK_local!(QQ,ielement,lobatto,radau,coord)
        elseif option == "K_with_BC_terms"
            get_KK_local!(QQ,ielement,lobatto,radau,coord,explicit_BC_terms=true)
        elseif option == "J"
            get_KJ_local!(QQ,ielement,lobatto,radau,coord)
        elseif option == "L"
            get_LL_local!(QQ,ielement,lobatto,radau,coord)
        elseif option == "L_with_BC_terms"
            get_LL_local!(QQ,ielement,lobatto,radau,coord,explicit_BC_terms=true)
        end
        return nothing
end

function get_MM_local!(QQ,ielement,
        lobatto::gausslegendre_base_info,
        radau::gausslegendre_base_info, 
        coord)
        
        scale_factor = coord.element_scale[ielement]
        shift_factor = coord.element_shift[ielement]
        if coord.name == "vperp" # assume integrals of form int^infty_0 (.) vperp d vperp
            # extra scale and shift factors required because of vperp in integral
            if ielement > 1 || coord.irank > 0 # lobatto points
                @. QQ =  (shift_factor*lobatto.M0 + scale_factor*lobatto.M1)*scale_factor
            else # radau points 
                @. QQ =  (shift_factor*radau.M0 + scale_factor*radau.M1)*scale_factor
            end
        else # assume integrals of form int^infty_-infty (.) d vpa
            @. QQ = lobatto.M0*scale_factor
        end 
        return nothing
end

function get_SS_local!(QQ,ielement,
        lobatto::gausslegendre_base_info,
        radau::gausslegendre_base_info, 
        coord)
        
        scale_factor = coord.element_scale[ielement]
        shift_factor = coord.element_shift[ielement]
        if coord.name == "vperp" # assume integrals of form int^infty_0 (.) vperp d vperp
            # extra scale and shift factors required because of vperp in integral
            if ielement > 1 || coord.irank > 0 # lobatto points
                @. QQ =  shift_factor*lobatto.S0 + scale_factor*lobatto.S1
                # boundary terms from integration by parts
                imin = coord.imin[ielement] - 1
                imax = coord.imax[ielement]
                QQ[1,1] -= coord.grid[imin]
                QQ[coord.ngrid,coord.ngrid] += coord.grid[imax]
            else # radau points 
                @. QQ =  shift_factor*radau.S0 + scale_factor*radau.S1
                # boundary terms from integration by parts
                imax = coord.imax[ielement]
                QQ[coord.ngrid,coord.ngrid] += coord.grid[imax]
            end
        else # assume integrals of form int^infty_-infty (.) d vpa
            @. QQ = lobatto.S0
            # boundary terms from integration by parts
            QQ[1,1] -= 1.0
            QQ[coord.ngrid,coord.ngrid] += 1.0
        end
        return nothing
end

function get_KK_local!(QQ,ielement,
        lobatto::gausslegendre_base_info,
        radau::gausslegendre_base_info, 
        coord;explicit_BC_terms=false)
        
        scale_factor = coord.element_scale[ielement]
        shift_factor = coord.element_shift[ielement]
        if coord.name == "vperp" # assume integrals of form int^infty_0 (.) vperp d vperp
            # extra scale and shift factors required because of vperp in integral
            # P0 factors make this a d^2 / dvperp^2 rather than (1/vperp) d ( vperp d (.) / d vperp)
            if ielement > 1 || coord.irank > 0 # lobatto points
                @. QQ =  (shift_factor/scale_factor)*lobatto.K0 + lobatto.K1 - lobatto.P0
                # boundary terms from integration by parts
                if explicit_BC_terms  
                    imin = coord.imin[ielement] - 1
                    imax = coord.imax[ielement]
                    @. QQ[1,:] -= coord.grid[imin]*lobatto.Dmat[1,:]/scale_factor
                    @. QQ[coord.ngrid,:] += coord.grid[imax]*lobatto.Dmat[coord.ngrid,:]/scale_factor  
                end
            else # radau points 
                @. QQ =  (shift_factor/scale_factor)*radau.K0 + radau.K1 - radau.P0
                # boundary terms from integration by parts
                if explicit_BC_terms  
                    imax = coord.imax[ielement]
                    @. QQ[coord.ngrid,:] += coord.grid[imax]*radau.Dmat[coord.ngrid,:]/scale_factor
                end
            end
        else # assume integrals of form int^infty_-infty (.) d vpa
            @. QQ = lobatto.K0/scale_factor
            # boundary terms from integration by parts
            if explicit_BC_terms
                @. QQ[1,:] -= lobatto.Dmat[1,:]/scale_factor
                @. QQ[coord.ngrid,:] += lobatto.Dmat[coord.ngrid,:]/scale_factor
            end
        end
        return nothing
end

# second derivative matrix with vperp^2 Jacobian factor if 
# coord is vperp. Not useful for the vpa coordinate
function get_KJ_local!(QQ,ielement,
        lobatto::gausslegendre_base_info,
        radau::gausslegendre_base_info, 
        coord)
        
        scale_factor = scale_factor_func(coord.L,coord.nelement_global)
        shift_factor = shift_factor_func(coord.L,coord.nelement_global,coord.nelement_local,coord.irank,ielement) + 0.5*coord.L
        if coord.name == "vperp" # assume integrals of form int^infty_0 (.) vperp d vperp
            # extra scale and shift factors required because of vperp^2 in integral
            if ielement > 1 || coord.irank > 0 # lobatto points
                @. QQ = (lobatto.K0*((shift_factor^2)/scale_factor) +
                         lobatto.K1*2.0*shift_factor +
                         lobatto.K2*scale_factor)
            else # radau points 
                @. QQ =  (radau.K0*((shift_factor^2)/scale_factor) +
                         radau.K1*2.0*shift_factor +
                         radau.K2*scale_factor)
            end
        else # assume integrals of form int^infty_-infty (.) d vpa
            @. QQ = lobatto.K0/scale_factor
        end
        return nothing
end

function get_LL_local!(QQ,ielement,
        lobatto::gausslegendre_base_info,
        radau::gausslegendre_base_info, 
        coord;explicit_BC_terms=false)
        
        scale_factor = coord.element_scale[ielement]
        shift_factor = coord.element_shift[ielement]
        if coord.name == "vperp" # assume integrals of form int^infty_0 (.) vperp d vperp
            # extra scale and shift factors required because of vperp in integral
            #  (1/vperp) d ( vperp d (.) / d vperp)
            if ielement > 1 || coord.irank > 0 # lobatto points
                @. QQ =  (shift_factor/scale_factor)*lobatto.K0 + lobatto.K1
                # boundary terms from integration by parts
                if explicit_BC_terms  
                    imin = coord.imin[ielement] - 1
                    imax = coord.imax[ielement]
                    @. QQ[1,:] -= coord.grid[imin]*lobatto.Dmat[1,:]/scale_factor
                    @. QQ[coord.ngrid,:] += coord.grid[imax]*lobatto.Dmat[coord.ngrid,:]/scale_factor
                end
            else # radau points 
                @. QQ =  (shift_factor/scale_factor)*radau.K0 + radau.K1
                # boundary terms from integration by parts
                if explicit_BC_terms  
                    imax = coord.imax[ielement]
                    @. QQ[coord.ngrid,:] += coord.grid[imax]*radau.Dmat[coord.ngrid,:]/scale_factor
                end
            end
        else # d^2 (.) d vpa^2 -- assume integrals of form int^infty_-infty (.) d vpa
            @. QQ = lobatto.K0/scale_factor
            # boundary terms from integration by parts
            if explicit_BC_terms 
                @. QQ[1,:] -= lobatto.Dmat[1,:]/scale_factor
                @. QQ[coord.ngrid,:] += lobatto.Dmat[coord.ngrid,:]/scale_factor
            end
        end
        return nothing
end

# mass matrix without vperp factor (matrix N)
# only useful for the vperp coordinate
function get_MN_local!(QQ,ielement,
        lobatto::gausslegendre_base_info,
        radau::gausslegendre_base_info, 
        coord)
        
        scale_factor = coord.element_scale[ielement]
        if coord.name == "vperp" # assume integrals of form int^infty_0 (.) vperp d vperp
            # extra scale and shift factors required because of vperp in integral
            if ielement > 1 || coord.irank > 0 # lobatto points
                @. QQ =  lobatto.M0*scale_factor
            else # radau points 
                @. QQ =  radau.M0*scale_factor
            end
        else # assume integrals of form int^infty_-infty (.) d vpa
            @. QQ = lobatto.M0*scale_factor
        end 
        return nothing
end

# mass matrix with vperp^2 factor (matrix R)
# only useful for the vperp coordinate
function get_MR_local!(QQ,ielement,
        lobatto::gausslegendre_base_info,
        radau::gausslegendre_base_info, 
        coord)
        
        scale_factor = coord.element_scale[ielement]
        shift_factor = coord.element_shift[ielement]
        if coord.name == "vperp" # assume integrals of form int^infty_0 (.) vperp d vperp
            # extra scale and shift factors required because of vperp in integral
            if ielement > 1 || coord.irank > 0 # lobatto points
                @. QQ =  (lobatto.M0*shift_factor^2 +
                          lobatto.M1*2.0*shift_factor*scale_factor +
                          lobatto.M2*scale_factor^2)*scale_factor
            else # radau points 
                @. QQ =  (radau.M0*shift_factor^2 +
                          radau.M1*2.0*shift_factor*scale_factor +
                          radau.M2*scale_factor^2)*scale_factor
            end
        else # assume integrals of form int^infty_-infty (.) d vpa
            @. QQ = lobatto.M0*scale_factor
        end 
        return nothing
end

# derivative matrix (matrix P, no integration by parts)
# with vperp Jacobian factor if coord is vperp (matrix P)
function get_PP_local!(QQ,ielement,
        lobatto::gausslegendre_base_info,
        radau::gausslegendre_base_info, 
        coord)
        
        scale_factor = coord.element_scale[ielement]
        shift_factor = coord.element_shift[ielement]
        if coord.name == "vperp" # assume integrals of form int^infty_0 (.) vperp d vperp
            # extra scale and shift factors required because of vperp in integral
            if ielement > 1 || coord.irank > 0 # lobatto points
                @. QQ =  lobatto.P0*shift_factor + lobatto.P1*scale_factor
            else # radau points 
                @. QQ =  radau.P0*shift_factor + radau.P1*scale_factor
            end
        else # assume integrals of form int^infty_-infty (.) d vpa
            @. QQ = lobatto.P0
        end 
        return nothing
end

# derivative matrix (matrix P, no integration by parts)
# with vperp^2 Jacobian factor if coord is vperp (matrix U)
# not useful for vpa coordinate
function get_PU_local!(QQ,ielement,
        lobatto::gausslegendre_base_info,
        radau::gausslegendre_base_info, 
        coord)
        
        scale_factor = coord.element_scale[ielement]
        shift_factor = coord.element_shift[ielement]
        if coord.name == "vperp" # assume integrals of form int^infty_0 (.) vperp d vperp
            # extra scale and shift factors required because of vperp in integral
            if ielement > 1 || coord.irank > 0 # lobatto points
                @. QQ =  (lobatto.P0*shift_factor^2 + 
                          lobatto.P1*2.0*shift_factor*scale_factor +
                          lobatto.P2*scale_factor^2)
            else # radau points 
                @. QQ =  (radau.P0*shift_factor^2 + 
                          radau.P1*2.0*shift_factor*scale_factor +
                          radau.P2*scale_factor^2)
            end
        else # assume integrals of form int^infty_-infty (.) d vpa
            @. QQ = lobatto.P0
        end 
        return nothing
end

"""
construction function for nonlinear diffusion matrices, only
used in the assembly of the collision operator
"""

function get_QQ_local!(QQ::Union{Array{mk_float,3},
        SubArray{Float64, 3, Array{Float64, 4}, 
        Tuple{Base.Slice{Base.OneTo{Int64}}, 
        Base.Slice{Base.OneTo{Int64}}, 
        Base.Slice{Base.OneTo{Int64}}, Int64}, true}},
        ielement,lobatto::gausslegendre_base_info,
        radau::gausslegendre_base_info, 
        coord,option)
  
        if option == "YY0" # mass-like matrix
            get_YY0_local!(QQ,ielement,lobatto,radau,coord)
        elseif option == "YY1" # first-derivative-like matrix
            get_YY1_local!(QQ,ielement,lobatto,radau,coord)
        elseif option == "YY2" # second-derivative-like matrix
            get_YY2_local!(QQ,ielement,lobatto,radau,coord)
        elseif option == "YY3" # first-derivative-like matrix
            get_YY3_local!(QQ,ielement,lobatto,radau,coord)
        end
        return nothing
end

function get_YY0_local!(QQ,ielement,
        lobatto::gausslegendre_base_info,
        radau::gausslegendre_base_info, 
        coord)
        
        scale_factor = coord.element_scale[ielement]
        shift_factor = coord.element_shift[ielement]
        if coord.name == "vperp" # assume integrals of form int^infty_0 (.) vperp d vperp
            # extra scale and shift factors required because of vperp in integral
            if ielement > 1 || coord.irank > 0 # lobatto points
                @. QQ =  (shift_factor*lobatto.Y00 + scale_factor*lobatto.Y01)*scale_factor
            else # radau points 
                @. QQ =  (shift_factor*radau.Y00 + scale_factor*radau.Y01)*scale_factor
            end
        else # assume integrals of form int^infty_-infty (.) d vpa
            @. QQ = lobatto.Y00*scale_factor
        end 
        return nothing
end

function get_YY1_local!(QQ,ielement,
        lobatto::gausslegendre_base_info,
        radau::gausslegendre_base_info, 
        coord)
        
        scale_factor = coord.element_scale[ielement]
        shift_factor = coord.element_shift[ielement]
        if coord.name == "vperp" # assume integrals of form int^infty_0 (.) vperp d vperp
            # extra scale and shift factors required because of vperp in integral
            if ielement > 1 || coord.irank > 0 # lobatto points
                @. QQ =  shift_factor*lobatto.Y10 + scale_factor*lobatto.Y11
            else # radau points 
                @. QQ =  shift_factor*radau.Y10 + scale_factor*radau.Y11
            end
        else # assume integrals of form int^infty_-infty (.) d vpa
            @. QQ = lobatto.Y10
        end 
        return nothing
end

function get_YY2_local!(QQ,ielement,
        lobatto::gausslegendre_base_info,
        radau::gausslegendre_base_info, 
        coord)
        
        scale_factor = coord.element_scale[ielement]
        shift_factor = coord.element_shift[ielement]
        if coord.name == "vperp" # assume integrals of form int^infty_0 (.) vperp d vperp
            # extra scale and shift factors required because of vperp in integral
            if ielement > 1 || coord.irank > 0 # lobatto points
                @. QQ =  (shift_factor/scale_factor)*lobatto.Y20 + lobatto.Y21
            else # radau points 
                @. QQ =  (shift_factor/scale_factor)*radau.Y20 + radau.Y21
            end
        else # assume integrals of form int^infty_-infty (.) d vpa
            @. QQ = lobatto.Y20/scale_factor
        end 
        return nothing
end

function get_YY3_local!(QQ,ielement,
        lobatto::gausslegendre_base_info,
        radau::gausslegendre_base_info, 
        coord)
        
        scale_factor = coord.element_scale[ielement]
        shift_factor = coord.element_shift[ielement]
        if coord.name == "vperp" # assume integrals of form int^infty_0 (.) vperp d vperp
            # extra scale and shift factors required because of vperp in integral
            if ielement > 1 || coord.irank > 0 # lobatto points
                @. QQ =  shift_factor*lobatto.Y30 + scale_factor*lobatto.Y31
            else # radau points 
                @. QQ =  shift_factor*radau.Y30 + scale_factor*radau.Y31
            end
        else # assume integrals of form int^infty_-infty (.) d vpa
            @. QQ = lobatto.Y30
        end 
        return nothing
end


end

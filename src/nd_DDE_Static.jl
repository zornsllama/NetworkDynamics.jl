module nd_DDE_Static_mod

using ..NetworkStructures
using ..ComponentFunctions
using ..Utilities


export nd_DDE_Static


@inline function prep_gd(dx::AbstractArray{T}, x::AbstractArray{T}, gd::GraphData{GDB, T, T}, gs) where {GDB, T}
    # Type matching
    if size(x) == (gs.dim_v,)
         swap_v_array!(gd, x)
         return gd
    else
         error("Size of x does not match the dimension of the system.")
    end
end

@inline function prep_gd(dx, x, gd, gs)
    # Type mismatch
    if size(x) == (gs.dim_v,)
        e_array = similar(dx, gs.dim_e)
        return GraphData(x, e_array, gs)
    else
        error("Size of x does not match the dimension of the system.")
   end
end


"""
nd_DDE_Static

vertices! has signature (dv, v, e_s, e_d, h_v, p ,t)
edges! has signature (e, v_s, v_d, h_v_s, h_v_d, p, t)
"""
@Base.kwdef struct nd_DDE_Static{G, T1, T2, GDB, elV, elE, Th<:AbstractArray{elV}}
    vertices!::T1
    edges!::T2
    graph::G #redundant?
    graph_structure::GraphStruct
    graph_data::GraphData{GDB, elV, elE}
    history::Th # fixing the type to Th is my first guess, maybe the histry should be stored
    # in the GraphData eventually
    parallel::Bool # enables multithreading for the core loop
end


function (d::nd_DDE_Static)(dx, x, h!, p, t)
    gs = d.graph_structure
    checkbounds_p(p, gs.num_v, gs.num_e)

    gd = prep_gd(dx, x, d.graph_data, d.graph_structure)

    #p[end] is now a list of lags, and history expected to be a VectorOfArrays whose ith component is the ith lag history.
    #thus A[k,j] gives the vertex k component of the jth lag history and A[j] gives the entire jth lag history
    for (i,lag) in enumerate(p[end])
        h!(d.history[i], p, t - lag)
    end

    @nd_threads d.parallel for i in 1:d.graph_structure.num_e
        maybe_idx(d.edges!, i).f!(
            get_edge(gd, i),
            get_src_vertex(gd, i),
            get_dst_vertex(gd, i),
            view(d.history, d.graph_structure.s_e_idx[i],:), view(d.history, d.graph_structure.d_e_idx[i],:), p_e_idx(p, i), t)
    end

    @assert size(dx) == size(x) "Sizes of dx and x do not match"

    @nd_threads d.parallel for i in 1:d.graph_structure.num_v
        maybe_idx(d.vertices!,i).f!(
            view(dx,d.graph_structure.v_idx[i]),
            get_vertex(gd, i),
            get_dst_edges(gd, i),
            view(d.history, d.graph_structure.v_idx[i],:), p_v_idx(p, i), t)
    end

    nothing
end

end

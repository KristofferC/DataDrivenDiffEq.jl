function DataDrivenDiffEq.get_fit_targets(::A, prob::AbstractDataDrivenProblem,
    basis::Basis) where {
                                 A <: AbstractDAGSRAlgorithm
                                 }

    return prob.X , DataDrivenDiffEq.get_implicit_data(prob)
end

function CommonSolve.solve!(prob::InternalDataDrivenProblem{A}) where {A <: AbstractDAGSRAlgorithm}
    @unpack alg, basis, testdata, traindata, control_idx, options, problem, kwargs = prob
    @unpack maxiters, progress, eval_expresssion = options

    # We do not use the normalized data here 
    # since our Basis contains parameters
    X, _, t, U = DataDrivenDiffEq.get_oop_args(problem)
    Y = DataDrivenDiffEq.get_implicit_data(problem)

    cache = init_cache(alg, basis, X, Y, U, t)
    
    p = progress ? ProgressMeter.Progress(maxiters, dt=1.0) : nothing

    for iter in 1:maxiters
        update_cache!(cache)
        if progress
            ProgressMeter.update!(p, iter, showvalues = [(:Algorithm, cache), (:Caches, cache.candidates[cache.keeps])])
        end
    end


    # Create the optimal basis
    min_loss, min_id = findmin(alg.loss, cache.candidates)
    best_cache = cache.candidates[min_id]

    p_best = get_parameters(best_cache)
    p_new = map(enumerate(ModelingToolkit.parameters(basis))) do (i, ps)
        DataDrivenDiffEq._set_default_val(Num(ps), p_best[i])
    end
    subs = Dict(a => b for (a, b) in zip(ModelingToolkit.parameters(basis), p_new))

    rhs = map(x->Num(x.rhs), equations(basis))
    rhs = collect(map(Base.Fix2(ModelingToolkit.substitute, subs), rhs))
    eqs, _ = best_cache.model(rhs, cache.p, best_cache.st)
    @info eqs

    new_basis = Basis(eqs, states(basis),
        parameters = p_new, iv = get_iv(basis),
        controls = controls(basis), observed = observed(basis),
        implicits = implicit_variables(basis),
        name = gensym(:Basis),
        eval_expression = eval_expresssion
    )

    new_problem = DataDrivenDiffEq.remake_problem(problem, p = p_best)
    
    rss = sum(abs2, new_basis(new_problem) .- DataDrivenDiffEq.get_implicit_data(new_problem))
    return DataDrivenSolution{typeof(rss)}(
        new_basis, DDReturnCode(1), alg, AbstractDataDrivenResult[], new_problem, 
        rss, length(p_new), prob
    )
end

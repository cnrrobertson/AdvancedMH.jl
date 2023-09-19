struct MALA{D} <: MHSampler
    proposal::D
    accepted_draws :: Int
    total_draws :: Int
end

MALA(p,ad,td) = MALA(p,ad,td)

# If we were given a RandomWalkProposal, just use that instead.
MALA(d::RandomWalkProposal) = MALA{typeof(d)}(d,0,0)

# Create a RandomWalkProposal if we weren't given one already.
MALA(d) = MALA(RandomWalkProposal(d))


struct GradientTransition{T<:Union{Vector, Real, NamedTuple}, L<:Real, G<:Union{Vector, Real, NamedTuple}} <: AbstractTransition
    params::T
    lp::L
    gradient::G
    accepted :: Bool
end

logdensity(model::DensityModelOrLogDensityModel, t::GradientTransition) = t.lp

propose(rng::Random.AbstractRNG, ::MALA, model) = error("please specify initial parameters")
function transition(sampler::MALA, model::DensityModelOrLogDensityModel, params, accepted)
    return GradientTransition(params, logdensity_and_gradient(model, params)..., accepted)
end

check_capabilities(model::DensityModelOrLogDensityModel) = nothing
function check_capabilities(model::AbstractMCMC.LogDensityModel)
    cap = LogDensityProblems.capabilities(model.logdensity)
    if cap === nothing
        throw(ArgumentError("The log density function does not support the LogDensityProblems.jl interface"))
    end

    if cap === LogDensityProblems.LogDensityOrder{0}()
        throw(ArgumentError("The gradient of the log density function is not defined: Implement `LogDensityProblems.logdensity_and_gradient` or use automatic differentiation provided by LogDensityProblemsAD.jl"))
    end
end

function AbstractMCMC.step(
    rng::Random.AbstractRNG,
    model::DensityModelOrLogDensityModel,
    sampler::MALA,
    transition_prev::GradientTransition;
    kwargs...
)
    check_capabilities(model)

    # Extract value and gradient of the log density of the current state.
    state = transition_prev.params
    logdensity_state = transition_prev.lp
    gradient_logdensity_state = transition_prev.gradient

    # Generate a new proposal.
    proposal = sampler.proposal
    candidate = propose(rng, proposal(gradient_logdensity_state), model, state)

    # Compute both the value of the log density and its gradient
    logdensity_candidate, gradient_logdensity_candidate = logdensity_and_gradient(
        model, candidate
    )

    # Compute the log ratio of proposal densities.
    logratio_proposal_density = q(
        proposal(-gradient_logdensity_candidate), state, candidate
    ) - q(proposal(-gradient_logdensity_state), candidate, state)

    # Compute the log acceptance probability.
    logα = logdensity_candidate - logdensity_state + logratio_proposal_density

    # Decide whether to return the previous params or the new one.
    transition = if -Random.randexp(rng) < logα
        accepted_draws = sampler.accepted_draws + 1
        GradientTransition(candidate, logdensity_candidate, gradient_logdensity_candidate, true)
    else
        accepted_draws = sampler.accepted_draws
        candidate = transition_prev.params
        lp = transition_prev.lp
        gradient = transition_prev.gradient
        GradientTransition(candidate, lp, gradient, false)
    end
    sampler = MALA(sampler.proposal, accepted_draws, sampler.total_draws+1)

    return transition, transition
end

"""
    logdensity_and_gradient(model::AdvancedMH.DensityModelOrLogDensityModel, params)

Return the value and gradient of the log density of the parameters `params` for the `model`.
"""
logdensity_and_gradient(::DensityModelOrLogDensityModel, ::Any)

function logdensity_and_gradient(model::AbstractMCMC.LogDensityModel, params)
    check_capabilities(model)
    return LogDensityProblems.logdensity_and_gradient(model.logdensity, params)
 end



# This is the internal Job structure
# TODO save the file and line number for the job definition so we can give clear debugging information
abstract type AbstractJob end

mutable struct ScheduledJob{T<:AbstractTarget}
    job_id::UInt64
    target::T
    data
    function ScheduledJob(job_id, target, data)
        returned_value_type = typeof(data)
        expected_type = return_type(target)
        if !(returned_value_type <: expected_type)
            throw(ArgumentError("Type of data must be a subtype of the target return type"))
    
        end
        return new{typeof(target)}(job_id, target,data)
    end
end


# This is what an executed Job will return
return_type(sj::ScheduledJob) = return_type(sj.target)
Base.convert(::Type{ScheduledJob}, ::Nothing) = ScheduledJob(zero(UInt64), NoTarget(), nothing)

# This is the interface for a Job. They dispatch on job type
get_dependencies(job) = nothing
get_target(job) = nothing
run_process(job, dependencies, target) = nothing

# Similar interface for ScheduledJob
get_dependencies(r::ScheduledJob) = r.dependencies
get_target(r::ScheduledJob) = r.target
get_result(t::Dagger.EagerThunk) = get_result(fetch(t))
get_result(j::ScheduledJob{T}) where {T} = j.data::return_type(T)

# This are the accepted versions of containers of jobs that the user can define for depenencies
const AcceptableDependencyContainers = Union{
    Vector{<:AbstractJob},
    AbstractDict{Symbol, <:AbstractJob},
}

"""
    @Job(job_description)

Constructs a new job based on a description. 

## Description Format
```juila
MyNewJob = @Job begin
    # Paramters are the input values for the job 
    parameters = (param1::String, param2::Int, param)
    
    # Dependencies list jobs that should be inputs to this job (Optional)
    # They can be created programmatically using parameters, and must return an
    # <:AbstractJob, AbstractArray{<:AbstractJob}, or AbstractDict{Symbol, <:AbstractJob}
    dependencies = [[SomeJob(i) for i in 1:param2]; AnotherJob("input")]
    
    # Target is an output location to cache the result. If the target exists, the job will
    # be skipped and the cached result will be returned (Optional).
    target = FileTarget(joinpath(snf_path, "raw_tables", "\$month.csv"))
    
    # The process function will be executed when the job is called.
    # All parameters, `dependencies`, and `target` are defined in this scope.
    process = begin
        dep1_data = dependencies[1]
        x = do_logic(dep1_data, param1)
        write(target, x)
        return x
    end
end
```
"""
macro Job(job_description)
    # This returns a Dict of job parameters and their values
    job_features = extract_job_features(job_description)
    
    job_name = job_features[:name]

    if job_name == Expr(:block, :nothing)
        return :(throw(ArgumentError("Job definitions require a `name` field but none was provided.")))
    end

    # Cleaning the parameters passed in
    raw_parameters = job_features[:parameters]
    # This is the list of parameters including type annotations if applicable
    parameter_list = raw_parameters isa Symbol ? (raw_parameters,) : raw_parameters.args
    # This is just the names
    parameter_names = [arg isa Symbol ? arg : arg.args[1] for arg in parameter_list]

    # get_dependencies need to return an `AcceptableDependencyContainers` and target needs to return an <:AbstractTarget
    # these functions append some protections and raise errors if the function returns an upexpected type
    dependency_func = add_get_dep_return_type_protection(job_features[:dependencies])
    target_func = add_get_target_return_type_protection(job_features[:target])
    
    dependency_ex = unpack_input_function(:get_dependencies, job_name, parameter_names, dependency_func)
    target_ex = unpack_input_function(:get_target, job_name, parameter_names, target_func)
    process_ex = unpack_input_function(:run_process, job_name, parameter_names, job_features[:process], (:dependencies, :target))
    
    struct_def = :(struct $job_name <: Waluigi.AbstractJob end)
    push!(struct_def.args[3].args, parameter_list...)

    # TODO: check if there is already a struct defined that is a complete match (name, fields, types)
    # if there is, then just emit the functions so since the user is probably just trying to 
    # edit the implementation of a funciton

    return quote
        $(esc(struct_def))
        $(esc(dependency_ex))
        $(esc(target_ex))
        $(esc(process_ex))
    end
end


function extract_job_features(job_description)

    job_features = Dict{Symbol,Any}()
    for element in job_description.args
        if element isa LineNumberNode
            continue
        end
        feature_name = element.args[1]
        if !(feature_name in (:name, :dependencies, :target, :process, :parameters))
            error("Got feature name $feature_name. Expected one of :name, :dependencies, :target, :process, :parameters.")
        end
        job_features[feature_name] = element.args[2]
    end

    for feature in (:name, :dependencies, :target, :process)
        if !(feature in keys(job_features))
            job_features[feature] = Expr(:block, :nothing)
        end
    end

    if !(:parameters in keys(job_features)) || job_features[:parameters] == :nothing
        job_features[:parameters] = :(())
    end

    return job_features
end


function unpack_input_function(function_name, job_name, parameter_names, function_body, additional_inputs=())
    return quote
        function Waluigi.$function_name(job::$job_name, $(additional_inputs...))
            let $((:($name = job.$name) for name in parameter_names)...)
                $function_body
            end
        end
    end
end



function add_get_dep_return_type_protection(func_block)
    return quote
        t = begin
            $func_block
        end
        corrected_deps = if t isa Nothing
            Waluigi.AbstractJob[]
        elseif t isa Waluigi.AbstractJob
            typeof(t)[t]
        elseif t isa Waluigi.AcceptableDependencyContainers
            t
        elseif t isa Type && t <: Waluigi.AbstractJob
            throw(ArgumentError("""The dependencies definition in $(typeof(job)) returned a AbstractJob type,\
but dependencies must be an instance of a job. Try calling the job like `$(t)(args...)`"""))
        else
            throw(ArgumentError("""The dependencies definition in $(typeof(job)) returned a $(t) \
which is not one of the accepted return types. It must return one of the following: \
<: AbstractJob, AbstractArray{<:AbstractJob}, Dict{Symbol, <:AbstractJob}"""))
        end
        return corrected_deps
    end
end


function add_get_target_return_type_protection(func_block)
    return quote
        t = begin
            $func_block
        end
        corrected_target = if t isa Nothing
            # TODO need to find a way to parameterize when no target is specified
            Waluigi.NoTarget{Any}()
        elseif t isa Waluigi.AbstractTarget
            t
        else
        throw(ArgumentError("""The target definition definition in $(typeof(job)) returned a $(typeof(t)), \
but target must return `nothing` or `<:AbstractTarget`"""))
        end
        return corrected_target
    end
end


# Vision
Waliugi should provide a seemless interface for constructing data pipelines. Users just need 
to define an job that has three parts:
* a list of jobs on which the current job depends 
* a target which holds the resulting data. Can be a local file, a database table, etc
* process function that providest the steps for creating the data

The workflow should be

Defining a list of jobs, calling `run()` on the final job, and then Waliuigi will
spawn all the dependent jobs required. If a job is already done, then it will read the target
and return that data. `run()` will return a Result object which contains references to the 
results of the depenencies, the target, and the data created by the job.

We will lean on Dagger.jl for the backend infrastructure which schedules jobs, mantains the
graph of dependencies, and provides visualizations of the processes. 

# TODO
* Investigate using Dagger Checkpoints 
x = Dagger.delayed(sum;
               options=Dagger.Sch.ThunkOptions(;
                   checkpoint=(thunk,result)->begin
                       open("checkpoint.bin", "w") do io
                           serialize(io, collect(result))
                       end
                   end,
                   restore=(thunk)->begin
                                dump(thunk)
                                   open("checkpoint.bin", "r") do io
                           Dagger.tochunk(deserialize(io))
                                           end
                   end)
               )([5,6])

* Consider using get_dependencies to improve type inference on NoTarget{Any}
* Docs for custom targets

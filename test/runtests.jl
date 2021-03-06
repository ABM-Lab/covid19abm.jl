using covid19abm
const cv = covid19abm
using Test

const infectiousstates = (cv.LAT, cv.MILD, cv.MISO, cv.INF, cv.IISO, cv.HOS, cv.ICU)


@testset "parameters" begin 
    ip = ModelParameters()
    mod_ip = cv.p ## get the module parameters    
    ## set random parameters 
    ip.β = 99
    ip.prov = :noknownlocation 
    ip.τmild = 1 ## days before they self-isolate for mild cases
    ip.fmild = 0.05  ## percent of people practice self-isolation
    ip.fsevere = 0.80 # fixed at 0.80, always within 1 day. 
    ip.eldq = 0.0 ## percentage quarantine of 60+ individuals, removes from chain of transmission
    ip.calibration = false 
    ip.modeltime = 500    
    reset_params(ip)
    for x in propertynames(cv.p)
        @test getfield(ip, x) == getfield(mod_ip, x)
    end
end

@testset "init" begin
    cv.reset_params_default()
    initialize()

    ## age groups
    inmodel = (1, 2, 3, 4, 5) ## possible age groups in model
    ags = []  
    for x in cv.humans
        push!(ags, x.ag)
        @test x.ag in inmodel
        @test x.exp == 999
        @test x.health == cv.SUS
        @test x.swap == cv.UNDEF
        @test x.iso == false
        @test x.isovia == :null
        @test x.tis == 0
        @test x.exp == 999
        @test x.sickfrom == cv.UNDEF
    end
    @test length(unique(ags)) == length(inmodel) # check if all age groups are sampled
    
    ## insert_infected check if infected person is added in the correct age group
    for ag in inmodel 
        initialize() # reset population
        insert_infected(cv.INF, 1, ag) # 1 infected in age group ag
        @test length(findall(x -> x.health == cv.INF && x.ag == ag, cv.humans)) == 1
    end

    ## check if the initial infected person is NOT IISO 
    cv.p.fsevere = 0.0 
    initialize() # reset population
    insert_infected(cv.INF, 1, 1) # 1 infected in age group ag
    @test length(findall(x -> x.health == cv.INF && x.swap == cv.REC, cv.humans)) == 1

    ## check if the initial infected person is REC (since simpleinf function only puts them to REC)
    cv.p.fsevere = 1.0 
    initialize() # reset population
    insert_infected(cv.INF, 1, 1) # 1 infected in age group ag
    @test length(findall(x -> x.health == cv.INF && x.swap == cv.REC, cv.humans)) == 1

    ## check if durations are properly set 
    initialize() 
    randhumans = rand(1:10000, 100) # select 100 random humans, no need to test all 10000
    for i in randhumans
        @test minimum(humans[i].dur) != 0
    end
end

@testset "transitions" begin
    cv.reset_params_default()
    initialize()
    
    ## check if time in state is up by one
    cv.time_update()
    for x in cv.humans 
        @test x.tis == 1  
        @test x.exp == 999
        @test x.health == cv.SUS
        @test x.swap == cv.UNDEF ## shouldn't set a swap 
    end

    for x in cv.humans 
        x.exp = 0 ## this will trigger a swap
    end
    @test_throws ErrorException("swap expired, but no swap set.") cv.time_update()

    #check if it goes through all the move compartments and see if health/swap changes
    
    for h in 2:9  ## latent to ded, ignore susceptible
        initialize()
        rh = cv.HEALTH(h)
        for x in humans 
            x.swap = rh
            x.exp = 0 ## to force the swap
        end
        time_update() ## since tis > exp 
        for x in humans[1:5]
            @test x.health == rh
            if rh ∈ infectiousstates  ## for all states, except rec/ded there should be a swap
                @test x.swap != cv.UNDEF
            end
        end    
    end

    # CHECKING LATENT
    initialize()
    x = humans[1]
    x.ag = 1 ## move to the first age group manually.
    myp = cv.ModelParameters()   

    # check basic variables
    cv.reset_params(myp)
    move_to_latent(x)
    @test x.swap ∈ (cv.ASYMP, cv.PRE)
    @test x.iso == false
    @test x.doi == 0 
    @test x.tis == 0 
    @test x.exp == x.dur[1]

    # check split between asymp/pre
    myp.fasymp = 0.0   
    cv.reset_params(myp)
    move_to_latent(x)
    @test x.swap == cv.PRE

    myp.fasymp = 1.0
    cv.reset_params(myp)
    move_to_latent(x)
    @test x.swap == cv.ASYMP

    # CHECKING PRE
    initialize()
    x = humans[1]
    cv.reset_params(myp)
    move_to_pre(x) 
    @test x.health == cv.PRE 
    @test x.swap ∈ (cv.MILD, cv.INF)
   
    ## check if individual moves through mild, miso through fmild, tmild parameters
    initialize()
    x = humans[1]
    x.ag = 1 ## move to the first age group manually.
    x.iso = false ## turn this off so we can test the effect of fmild, tmild
    myp.fmild = 0.0
    cv.reset_params(myp)
    move_to_mild(x)
    @test x.swap == cv.REC

    myp.fmild = 1.0
    myp.τmild = 1
    cv.reset_params(myp)
    move_to_mild(x)
    @test x.swap == cv.MISO
    @test x.exp == 1
    
    time_update() 
    @test x.health == cv.MISO
    @test x.swap == cv.REC
    
    ## todo: check if x.iso and x.isovia property are set correctly. 
    # 1) check if they are isolated through quarantine
    myp = cv.ModelParameters()   
    myp.eldq = 1.0  ## turn on eldq
    myp.eldqag = 4
    cv.reset_params(myp)
    cv.initialize()    
    for x in cv.humans
        if x.ag  == myp.eldqag 
            @test x.iso == true 
            @test x.isovia == :qu
        else 
            @test x.iso == false 
            @test x.isovia == :null
        end
    end
    # 2) check if they are isolated through presymptomatic capture 
    # no need to test for mild/inf movement since it's a simple assignment in code
    # more important to check through `main` when all the function dynamics are happening. 
    myp = cv.ModelParameters()   
    myp.eldq = 0.0  ## turn off eldq
    myp.fsevere = 0.0 ## turn on fsevere
    myp.fmild = 0.0
    myp.fpreiso = 1.0 
    cv.reset_params(myp)
    cv.initialize()  
    for x in cv.humans 
        cv.move_to_pre(x)
        @test x.iso == true && x.isovia == :pi
    end
end


@testset "tranmission" begin
    cv.reset_params_default()
    cv.initialize()
    grps = cv.get_ag_dist()
    
    # since beta = 0 default, and everyone sus
    totalinf = cv.dyntrans(1, grps)  
    @test totalinf == 0

    # check with only a single infected person 
    insert_infected(cv.INF, 1, 1) # 1 infected in age group ag
    totalinf = cv.dyntrans(1, grps)  
    @test totalinf == 0 # still zero cuz beta = 0

    # now change beta 
    cv.reset_params(ModelParameters(β = 1.0))
    totalinf = cv.dyntrans(1, grps)  
    @test totalinf > 0 ## actually may still be zero because of stochasticity but very unliekly 

    ## somehow check the transmission reduction and number of contacts
end

@testset "calibration" begin
    # to do, run the model and test total number of infections 
    myp = ModelParameters()
    myp.β = 1.0
    myp.prov = :ontario
    myp.calibration = true
    myp.fmild = 0.0 
    myp.fsevere = 0.0
    myp.fpreiso = 0.0
    myp.fasymp = 0.5
    myp.initialinf = 1
    cv.reset_params(myp)
    cv.initialize()
    grps = cv.get_ag_dist()
    cv.insert_infected(cv.PRE, 1, 4)
    # find the single insert_presymptomatic person
    h = findall(x -> x.health == cv.PRE, cv.humans)
    x = humans[h[1]]
    @test length(h) == 1
    @test x.ag == 4
    @test x.swap ∈ (cv.ASYMP, cv.MILD, cv.INF) ## always true for calibration 
    for i = 1:20 ## run for 20 days 
        cv.dyntrans(i, grps)
        cv.time_update()
    end
    @test x.health == cv.REC  ## make sure the initial guy recovered
    @test x.exp == 999
    ## everyone should really be in latent (or susceptible) except the recovered guy
    all = findall(x -> x.health ∈ (cv.PRE, cv.ASYMP, cv.MILD, cv.MISO, cv.INF, cv.IISO, cv.HOS, cv.ICU, cv.DED), cv.humans)
    @test length(all) == 0
    ## to do, make sure everyone stays latent
    
end

@testset "contact trace" begin
    # todo: check interaction between doi and tracestart, default values
    # myp = ModelParameters()
    # myp.β = 1.0 
    # cv.reset_params(myp)
    # cv.initialize()
    # hdx = rand(1:10000, 20) ## sample 20 humans instead of all 10000 
    # for i in hdx
    #     x = cv.humans[i] 
    #     cv.ct_dynamics(x)
    #     @test x.tracing == false ## since fctcapture = 0.0
    #     @test x.tracinguntil == -1
    #     @test x.tracedby == 0 
    #     @test x.tracedxp == 0
    # end
    # ## test the contact_tracing() function 
    # cv.initialize()    
    # grps = cv.get_ag_dist()
    # myp.fctcapture = 1.0 
    # myp.fasymp = 0.0  # to force no asymp
    # cv.reset_params(myp)
    # cv.initialize()    
    # tracer = cv.humans[1]
    # cv.move_to_pre(tracer) # newly presymptomatic
    # cv.ct_dynamics(tracer) # will turn on tracing
    # @test tracer.tracing == true 
    # @test tracer.tracinguntil == 3

    # cv.dyntrans(1, grps) ## go through a single tranmission cycle
    # alltraced = findall(x -> x.tracedby > 0, cv.humans) ## since we havn't turned fctcapture > 0
    # @test length(alltraced) > 0
    # for i in alltraced
    #     y = cv.humans[i]
    #     @test y.tracedby == 1 ## since we used the first human as the tracing contact
    #     @test y.tracedxp == 14
    #     @test y.iso == false ## the first human is not in INF stage yet.. still in presymp
    #     @test y.isovia == :null 
    # end
    # ## time update calls the ctdynamics function.. have to use this because otherwise tracer is stuck on PRE day 1. 
    # cv.time_update() 
    # #cv.ct_dynamics(tracer) # will turn on tracing
    # @test tracer.tracing == true 
    # @test tracer.tracinguntil == 2 
    # for i in alltraced
    #     y = cv.humans[i]
    #     @test y.tracedby == 1 ## since we used the first human as the tracing contact
    #     @test y.tracedxp == 14
    #     @test y.iso == false ## the first human is not in INF stage yet.. still in presymp
    #     @test y.isovia == :null 
    # end
    # cv.time_update()
    # @test tracer.tracing == true 
    # @test tracer.tracinguntil == 1
    # for i in alltraced
    #     y = cv.humans[i]
    #     @test y.tracedby == 1 ## since we used the first human as the tracing contact
    #     @test y.tracedxp == 14
    #     @test y.iso == false ## the first human is not in INF stage yet.. still in presymp
    #     @test y.isovia == :null 
    # end
    # cv.time_update()
    # @test tracer.tracing == false  
    # @test tracer.tracinguntil == 0
    # # for i in alltraced
    # #     y = cv.humans[i]
    # #     @test y.tracedby == 1 
    # #     @test y.tracedxp == 13 ## one less day from 14
    # #     @test y.iso == true ## the first human is not in INF stage yet.. still in presymp
    # #     @test y.isovia == :ct 
    # # end
    myp = cv.ModelParameters()    
    myp.fctcapture = 1.0 # force contact tracing
    myp.fasymp = 0.0 # force to pre
    cv.reset_params(myp)
    cv.initialize()
    x = cv.humans[1] 
    @test x.tracestart == -1 
    @test x.traceend == -1

    cv.move_to_latent(x)
    cv.ct_dynamics(x) # since ct_dynamics will run when move_to_latent will run in time update func
    @test x.swap == cv.PRE 
    @test x.doi == 0 
    @test x.tis == 0 
    @test x.exp == x.dur[1]
    @test x.tracestart > 0
    @test x.traceend > 0 
    
    # go through entire inf period 
    totalinfperiod = x.dur[1] + x.dur[3] + x.dur[4]
    totaltracedays = 0
    for i = 1:totalinfperiod
        # dyntrans
        cv.time_update()
        @test x.doi == i # should increase with the counter.
        if x.doi >= x.tracestart && x.doi < x.traceend
            @test x.tracing == true 
            totaltracedays += 1
            println("trace true in health: $(x.HEALTH), tis: $(x.tis)")
        end
    end
    @test totaltracedays == cv.p.cdaysback
end

@testset "main run" begin 
    ## run model with high beta 
    myp = cv.ModelParameters()
    myp.β = 0.0525 
    myp.prov = :newyork    
    ## run empty scenario
    ## this wont return calibrated scenario since fasymp = 0
    myp.τmild = 0
    myp.fmild = 0.0
    myp.fsevere = 0.0
    myp.eldq = 0.0  
    myp.fasymp = 0.5
    myp.fpre = 1.0
    myp.fpreiso = 0.0 
    myp.tpreiso = 0
    myp.fctcapture = 0.0
    cv.runsim(1, myp) # warm up the functions
    println("time with contact tracing off:")
    @time results = cv.main(myp)

    myp.fctcapture = 1.0
    cv.runsim(1, myp)
    println("time with contact tracing on:")
    @time results = cv.main(myp)
    
#     function string_or_char(s::SubString)
#         length(s) == 1 && return first(s)
#         return String(s)
#     end
#     arr = Union{Char,String}[]
# for i in split_string
#     push!(arr, string_or_char(i))
# end

    # function addday(n)
    #     strtorep = "---" * "\u00B7"
    #     str = ""
    #     for i = 1:n 
    #         str =str * strtorep 
    #     end
    #     str = str[1:end-1]
    #     str = " " * str * " "
    #     return str
    # end
    

    # function printascii_epi(x) 
    #     fs = "" 
    #     fs = fs * "L" * addday(x.dur[1])
     
    #     fs = fs * "P" * addday(x.dur[3])
    #     fs = fs * "S" * addday(x.dur[4])
    #     return fs
    # end
   

end



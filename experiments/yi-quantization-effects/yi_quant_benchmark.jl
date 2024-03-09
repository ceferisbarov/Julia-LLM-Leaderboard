# # Yi model quantization benchmark
#
# Evaluate effect of different quantizations on Yi models

# ## Imports
using JuliaLLMLeaderboard
using PromptingTools
const PT = PromptingTools

# ## Run for a single test case
device = "NVIDIA-RTX-4090" # "Apple-MacBook-Pro-M1" or "NVIDIA-GTX-1080Ti", broadly "manufacturer-model"
# export CUDA_VISIBLE_DEVICES=0

# How many samples to generate for each model/prompt combination
num_samples = 10

# Select models to run
model_options = [
    "yi:34b-chat-fp16",
    "yi:34b-chat-q8_0",
    "yi:34b-chat-q6_K",
    "yi:34b-chat-q5_K_M",
    "yi:34b-chat-q5_K_S",
    "yi:34b-chat-q5_0",
    "yi:34b-chat-q4_K_M",
    "yi:34b-chat-q4_0",
    "yi:34b-chat-q3_K_L",
    "yi:34b-chat-q3_K_S",
    "yi:34b-chat-q2_K",
]

# Select prompt templates to run (for reference check: `aitemplates("Julia")`)
prompt_options = [
    "JuliaExpertCoTTask",
    "JuliaExpertAsk",
    "InJulia",
    ## "AsIs", # no need to prove that it's worse
    "JuliaRecapTask",
    "JuliaRecapCoTTask",
]

# Define the schema for unknown models, eg, needed if you use non-OpenAI models, provide a key for each model you use
schema_lookup = Dict{String, Any}(model_options .=> Ref(PT.OllamaSchema()))

# ## Run Benchmark - High-level Interface
fn_definitions = find_definitions("code_generation")

# or if you want only one test case:
# fn_definitions = [
# joinpath("code_generation", "utility_functions", "clean_column", "definition.toml"),
# ]

evals = run_benchmark(; fn_definitions,
    models = model_options,
    prompt_labels = prompt_options,
    experiment = "yi-quantization-effects-default",
    auto_save = true, verbose = true,
    device,
    save_dir = "yi-quantization-effects",
    num_samples = num_samples, schema_lookup, http_kwargs = (; readtimeout = 200),
    api_kwargs = (; options = (; num_gpu = 99)));

# evals = run_benchmark(; fn_definitions,
#     models = model_options,
#     prompt_labels = prompt_options,
#     experiment = "yi-quantization-effects-temp0.3",
#     auto_save = true, verbose = true,
#     device,
#     save_dir = "yi-quantization-effects",
#     num_samples = num_samples, schema_lookup, http_kwargs = (; readtimeout = 1000),
#     api_kwargs = (; options = (; num_gpu = 99, temperature = 0.3)));

evals = run_benchmark(; fn_definitions,
    models = model_options,
    prompt_labels = prompt_options,
    experiment = "magicoder-quantization-effects-temp0.5",
    auto_save = true, verbose = true,
    device,
    save_dir = "magicoder-quantization-effects",
    num_samples = num_samples, schema_lookup, http_kwargs = (; readtimeout = 100),
    api_kwargs = (; options = (; num_gpu = 99, temperature = 0.5)));

# ## Find missing samples
using DataFramesMeta
using Statistics
df_all = allcombinations(DataFrame,
    "model" => model_options,
    "prompt_label" => prompt_options,
    "fn_definitions" => fn_definitions)
@rtransform!(df_all, :name=split(:fn_definitions, "/")[end - 1])

## Load data
df = load_evals("yi-quantization-effects"; max_history = 0)

# Overall summary by test case
df_missing = @chain df begin
    @rsubset :experiment == "yi-quantization-effects-temp0.5"
    # @rsubset :model=="yi:34b-chat-q3_K_L" :prompt_label=="JuliaExpertCoTTask"
    @by [:model, :prompt_label, :name] begin
        :score = mean(:score)
        :count_zeros = count(==(0), :score)
        :count = $nrow
    end
    leftjoin(df_all, _, on = [:model, :prompt_label, :name], validate = (true, true))
    @rtransform :count_missing = num_samples - coalesce(:count, 0)
    @rsubset :count_missing > 0
    @orderby -:count_missing
end
@by df_missing :name :count_missing=sum(:count_missing)

## fill missing benchmarks
for row in eachrow(df_missing)
    @info "Running $(row.model) / $(row.prompt_label) / $(row.name) for $(row.count_missing) samples"
    evals = run_benchmark(; fn_definitions = [row.fn_definitions],
        models = [row.model],
        prompt_labels = [row.prompt_label],
        experiment = "yi-quantization-effects",
        auto_save = true, verbose = true,
        device,
        save_dir = "yi-quantization-effects",
        num_samples = row.count_missing, schema_lookup,
        http_kwargs = (; readtimeout = 60),
        api_kwargs = (; options = (; num_gpu = 99)))
end

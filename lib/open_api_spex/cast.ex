defmodule OpenApiSpex.Cast do
  alias OpenApiSpex.{Reference, Schema}
  alias OpenApiSpex.Reference

  alias OpenApiSpex.Cast.{
    AllOf,
    AnyOf,
    Array,
    Discriminator,
    Error,
    Integer,
    Object,
    OneOf,
    Primitive,
    String
  }

  @type schema_or_reference :: Schema.t() | Reference.t()
  @type t :: %__MODULE__{
          value: term(),
          schema: schema_or_reference | nil,
          schemas: map(),
          path: [atom() | String.t() | integer()],
          key: atom() | nil,
          index: integer,
          errors: [Error.t()]
        }

  defstruct value: nil,
            schema: nil,
            schemas: %{},
            path: [],
            key: nil,
            index: 0,
            errors: []

  @spec cast(schema_or_reference | nil, term(), map()) :: {:ok, term()} | {:error, [Error.t()]}
  def cast(schema, value, schemas) do
    ctx = %__MODULE__{schema: schema, value: value, schemas: schemas}
    cast(ctx)
  end

  @spec cast(t()) :: {:ok, term()} | {:error, [Error.t()]}

  # nil schema
  def cast(%__MODULE__{value: value, schema: nil}),
    do: {:ok, value}

  def cast(%__MODULE__{schema: %Reference{}} = ctx) do
    schema = Reference.resolve_schema(ctx.schema, ctx.schemas)
    cast(%{ctx | schema: schema})
  end

  # nullable: true
  def cast(%__MODULE__{value: nil, schema: %{nullable: true}}) do
    {:ok, nil}
  end

  # nullable: false
  def cast(%__MODULE__{value: nil} = ctx) do
    error(ctx, {:null_value})
  end

  # Enum
  def cast(%__MODULE__{schema: %{enum: []}} = ctx) do
    cast(%{ctx | schema: %{ctx.schema | enum: nil}})
  end

  # Enum
  def cast(%__MODULE__{schema: %{enum: enum}} = ctx) when is_list(enum) do
    with {:ok, value} <- cast(%{ctx | schema: %{ctx.schema | enum: nil}}) do
      if value in enum do
        {:ok, value}
      else
        error(ctx, {:invalid_enum})
      end
    end
  end

  ## Specific types

  def cast(%__MODULE__{schema: %{type: :object, discriminator: discriminator}} = ctx)
      when is_map(discriminator),
      do: Discriminator.cast(ctx)

  def cast(%__MODULE__{schema: %{type: _, anyOf: schemas}} = ctx) when is_list(schemas),
    do: AnyOf.cast(ctx)

  def cast(%__MODULE__{schema: %{type: _, allOf: schemas}} = ctx) when is_list(schemas),
    do: AllOf.cast(ctx)

  def cast(%__MODULE__{schema: %{type: _, oneOf: schemas}} = ctx) when is_list(schemas),
    do: OneOf.cast(ctx)

  def cast(%__MODULE__{schema: %{type: :object}} = ctx),
    do: Object.cast(ctx)

  def cast(%__MODULE__{schema: %{type: :boolean}} = ctx),
    do: Primitive.cast_boolean(ctx)

  def cast(%__MODULE__{schema: %{type: :integer}} = ctx),
    do: Integer.cast(ctx)

  def cast(%__MODULE__{schema: %{type: :number}} = ctx),
    do: Primitive.cast_number(ctx)

  def cast(%__MODULE__{schema: %{type: :string}} = ctx),
    do: String.cast(ctx)

  def cast(%__MODULE__{schema: %{type: :array}} = ctx),
    do: Array.cast(ctx)

  def cast(%__MODULE__{schema: %{type: _other}} = ctx),
    do: error(ctx, {:invalid_schema_type})

  def cast(%{} = ctx), do: cast(struct(__MODULE__, ctx))
  def cast(ctx) when is_list(ctx), do: cast(struct(__MODULE__, ctx))

  # Add an error
  def error(ctx, error_args) do
    error = Error.new(ctx, error_args)
    {:error, [error | ctx.errors]}
  end

  def ok(%__MODULE__{value: value}), do: {:ok, value}

  def success(%__MODULE__{schema: schema} = ctx, schema_properties)
      when is_list(schema_properties) do
    schema_without_successful_validation_property =
      Enum.reduce(schema_properties, schema, fn property, schema ->
        %{schema | property => nil}
      end)

    {:cast, %{ctx | schema: schema_without_successful_validation_property}}
  end

  def success(%__MODULE__{schema: _schema} = ctx, schema_property) do
    success(ctx, [schema_property])
  end
end

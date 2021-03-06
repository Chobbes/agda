.. _reflection:

**********
Reflection
**********

Builtin types
-------------

Names
~~~~~

The built-in ``QNAME`` type represents quoted names and comes equipped with
equality, ordering and a show function.

::

  postulate Name : Set
  {-# BUILTIN QNAME Name #-}

  primitive
    primQNameEquality : Name → Name → Bool
    primQNameLess     : Name → Name → Bool
    primShowQName     : Name → String

Name literals are created using the ``quote`` keyword and can appear both in
terms and in patterns

::

  nameOfNat : Name
  nameOfNat = quote Nat

  isNat : Name → Bool
  isNat (quote Nat) = true
  isNat _           = false

Note that the name being quoted must be in scope.

Metavariables
~~~~~~~~~~~~~

Metavariables are represented by the built-in ``AGDAMETA`` type. They have
primitive equality, ordering and show::

  postulate Meta : Set
  {-# BUILTIN AGDAMETA Meta #-}

  primitive
    primMetaEquality : Meta → Meta → Bool
    primMetaLess     : Meta → Meta → Bool
    primShowMeta     : Meta → String

Builtin metavariables show up in reflected terms.

Literals
~~~~~~~~

Literals are mapped to the built-in ``AGDALITERAL`` datatype. Given the appropriate
built-in binding for the types ``Nat``, ``Float``, etc, the ``AGDALITERAL`` datatype
has the following shape:

::

    data Literal : Set where
      nat    : (n : Nat)    → Literal
      float  : (x : Float)  → Literal
      char   : (c : Char)   → Literal
      string : (s : String) → Literal
      name   : (x : Name)   → Literal
      meta   : (x : Meta)   → Literal

    {-# BUILTIN AGDALITERAL   Literal #-}
    {-# BUILTIN AGDALITNAT    nat     #-}
    {-# BUILTIN AGDALITFLOAT  float   #-}
    {-# BUILTIN AGDALITCHAR   char    #-}
    {-# BUILTIN AGDALITSTRING string  #-}
    {-# BUILTIN AGDALITQNAME  name    #-}
    {-# BUILTIN AGDALITMETA   meta    #-}

Patterns
~~~~~~~~

Reflected patterns are bound to the ``AGDAPATTERN`` built-in using the
following data type.

::

  data Pattern : Set where
    con    : (c : Name) (ps : List (Arg Pattern)) → Pattern
    dot    : Pattern
    var    : (s : String)  → Pattern
    lit    : (l : Literal) → Pattern
    proj   : (f : Name)    → Pattern
    absurd : Pattern

  {-# BUILTIN AGDAPATTERN   Pattern #-}
  {-# BUILTIN AGDAPATCON    con     #-}
  {-# BUILTIN AGDAPATDOT    dot     #-}
  {-# BUILTIN AGDAPATVAR    var     #-}
  {-# BUILTIN AGDAPATLIT    lit     #-}
  {-# BUILTIN AGDAPATPROJ   proj    #-}
  {-# BUILTIN AGDAPATABSURD absurd  #-}

Terms
~~~~~

Terms, sorts and clauses are mutually recursive and mapped to the ``AGDATERM``,
``AGDASORT`` and ``AGDACLAUSE`` built-ins respectively. Types are simply
terms. Terms use de Bruijn indices to represent variables.

::

  data Term : Set
  data Sort : Set
  Type = Term

  data Term where
    var       : (x : Nat) (args : List (Arg Term)) → Term
    con       : (c : Name) (args : List (Arg Term)) → Term
    def       : (f : Name) (args : List (Arg Term)) → Term
    lam       : (v : Visibility) (t : Abs Term) → Term
    pat-lam   : (cs : List Clause) (args : List (Arg Term)) → Term
    pi        : (a : Arg Type) (b : Abs Type) → Term
    agda-sort : (s : Sort) → Term
    lit       : (l : Literal) → Term
    meta      : (x : Meta) → List (Arg Term) → Term
    unknown   : Term -- Treated as '_' when unquoting.

  data Sort where
    set     : (t : Term) → Sort -- A Set of a given (possibly neutral) level.
    lit     : (n : Nat) → Sort  -- A Set of a given concrete level.
    unknown : Sort

  data Clause where
    clause        : (ps : List (Arg Pattern)) (t : Term) → Clause
    absurd-clause : (ps : List (Arg Pattern)) → Clause

  {-# BUILTIN AGDASORT    Sort   #-}
  {-# BUILTIN AGDATERM    Term   #-}
  {-# BUILTIN AGDACLAUSE  Clause #-}

  {-# BUILTIN AGDATERMVAR         var       #-}
  {-# BUILTIN AGDATERMCON         con       #-}
  {-# BUILTIN AGDATERMDEF         def       #-}
  {-# BUILTIN AGDATERMMETA        meta      #-}
  {-# BUILTIN AGDATERMLAM         lam       #-}
  {-# BUILTIN AGDATERMEXTLAM      pat-lam   #-}
  {-# BUILTIN AGDATERMPI          pi        #-}
  {-# BUILTIN AGDATERMSORT        agda-sort #-}
  {-# BUILTIN AGDATERMLIT         lit       #-}
  {-# BUILTIN AGDATERMUNSUPPORTED unknown   #-}

  {-# BUILTIN AGDASORTSET         set     #-}
  {-# BUILTIN AGDASORTLIT         lit     #-}
  {-# BUILTIN AGDASORTUNSUPPORTED unknown #-}

  {-# BUILTIN AGDACLAUSECLAUSE clause        #-}
  {-# BUILTIN AGDACLAUSEABSURD absurd-clause #-}

Absurd lambdas ``λ ()`` are quoted to extended lambdas with an absurd clause.

The built-in constructors ``AGDATERMUNSUPPORTED`` and ``AGDASORTUNSUPPORTED``
are translated to meta variables when unquoting.

Declarations
~~~~~~~~~~~~

There is a built-in type ``AGDADEFINITION`` representing definitions. Values of
this type is returned by the ``AGDATCMGETDEFINITION`` built-in :ref:`described
below <reflection-tc-monad>`.

::

  data Definition : Set where
    function    : (cs : List Clause) → Definition
    data-type   : (pars : Nat) (cs : List Name) → Definition  -- parameters and constructors
    record-type : (c : Name) → Definition                     -- name of data/record type
    data-cons   : (d : Name) → Definition                     -- name of constructor
    axiom       : Definition
    prim-fun    : Definition

  {-# BUILTIN AGDADEFINITION                Definition  #-}
  {-# BUILTIN AGDADEFINITIONFUNDEF          function    #-}
  {-# BUILTIN AGDADEFINITIONDATADEF         data-type   #-}
  {-# BUILTIN AGDADEFINITIONRECORDDEF       record-type #-}
  {-# BUILTIN AGDADEFINITIONDATACONSTRUCTOR data-cons   #-}
  {-# BUILTIN AGDADEFINITIONPOSTULATE       axiom       #-}
  {-# BUILTIN AGDADEFINITIONPRIMITIVE       prim-fun    #-}

Type errors
~~~~~~~~~~~

Type checking computations (see `below <Type checking computations_>`_) can
fail with an error, which is a list of ``ErrorPart``\s. This allows
metaprograms to generate nice errors without having to implement pretty
printing for reflected terms.

::

  -- Error messages can contain embedded names and terms.
  data ErrorPart : Set where
    strErr  : String → ErrorPart
    termErr : Term → ErrorPart
    nameErr : Name → ErrorPart

  {-# BUILTIN AGDAERRORPART       ErrorPart #-}
  {-# BUILTIN AGDAERRORPARTSTRING strErr    #-}
  {-# BUILTIN AGDAERRORPARTTERM   termErr   #-}
  {-# BUILTIN AGDAERRORPARTNAME   nameErr   #-}

.. _reflection-tc-monad:

Type checking computations
~~~~~~~~~~~~~~~~~~~~~~~~~~

Metaprograms, i.e. programs that create other programs, run in a built-in type
checking monad ``TC``::

  postulate
    TC       : ∀ {a} → Set a → Set a
    returnTC : ∀ {a} {A : Set a} → A → TC A
    bindTC   : ∀ {a b} {A : Set a} {B : Set b} → TC A → (A → TC B) → TC B

  {-# BUILTIN AGDATCM       TC       #-}
  {-# BUILTIN AGDATCMRETURN returnTC #-}
  {-# BUILTIN AGDATCMBIND   bindTC   #-}


The ``TC`` monad provides an interface to the Agda type checker using the
following primitive operations::

  postulate
    -- Unify two terms, potentially solving metavariables in the process.
    unify : Term → Term → TC ⊤

    -- Throw a type error. Can be caught by catchTC.
    typeError : ∀ {a} {A : Set a} → String → TC A

    -- Block a type checking computation on a metavariable. This will abort
    -- the computation and restart it (from the beginning) when the
    -- metavariable is solved.
    blockOnMeta : ∀ {a} {A : Set a} → Meta → TC A

    -- Backtrack and try the second argument if the first argument throws a
    -- type error.
    catchTC : ∀ {a} {A : Set a} → TC A → TC A → TC A

    -- Infer the type of a given term
    inferType : Term → TC Type

    -- Check a term against a given type. This may resolve implicit arguments
    -- in the term, so a new refined term is returned. Can be used to create
    -- new metavariables: newMeta t = checkType unknown t
    checkType : Term → Type → TC Term

    -- Compute the normal form of a term.
    normalise : Term → TC Term

    -- Get the current context. Returns the context in reverse order, so that
    -- it is indexable by deBruijn index.
    getContext : TC (List (Arg Type))

    -- Extend the current context with a variable of the given type.
    extendContext : ∀ {a} {A : Set a} → Arg Type → TC A → TC A

    -- Set the current context. Takes a context telescope with the outer-most
    -- entry first, in contrast to 'getContext'.
    inContext : ∀ {a} {A : Set a} → List (Arg Type) → TC A → TC A

    -- Quote a value, returning the corresponding Term.
    quoteTC : ∀ {a} {A : Set a} → A → TC Term

    -- Unquote a Term, returning the corresponding value.
    unquoteTC : ∀ {a} {A : Set a} → Term → TC A

    -- Create a fresh name.
    freshName : String → TC Name

    -- Declare a new function of the given type. The function must be defined
    -- later using 'defineFun'. Takes an Arg Name to allow declaring instances
    -- and irrelevant functions. The Visibility of the Arg must not be hidden.
    declareDef : Arg Name → Type → TC ⊤

    -- Define a declared function. The function may have been declared using
    -- 'declareDef' or with an explicit type signature in the program.
    defineFun : Name → List Clause → TC ⊤

    -- Get the type of a defined name. Replaces 'primNameType'.
    getType : Name → TC Type

    -- Get the definition of a defined name. Replaces 'primNameDefinition'.
    getDefinition : Name → TC Definition

  {-# BUILTIN AGDATCMUNIFY              unify              #-}
  {-# BUILTIN AGDATCMNEWMETA            newMeta            #-}
  {-# BUILTIN AGDATCMTYPEERROR          typeError          #-}
  {-# BUILTIN AGDATCMBLOCKONMETA        blockOnMeta        #-}
  {-# BUILTIN AGDATCMCATCHERROR         catchTC            #-}
  {-# BUILTIN AGDATCMINFERTYPE          inferType          #-}
  {-# BUILTIN AGDATCMCHECKTYPE          checkType          #-}
  {-# BUILTIN AGDATCMNORMALISE          normalise          #-}
  {-# BUILTIN AGDATCMGETCONTEXT         getContext         #-}
  {-# BUILTIN AGDATCMEXTENDCONTEXT      extendContext      #-}
  {-# BUILTIN AGDATCMINCONTEXT          inContext          #-}
  {-# BUILTIN AGDATCMQUOTETERM          quoteTC            #-}
  {-# BUILTIN AGDATCMUNQUOTETERM        unquoteTC          #-}
  {-# BUILTIN AGDATCMFRESHNAME          freshName          #-}
  {-# BUILTIN AGDATCMDECLAREDEF         declareDef         #-}
  {-# BUILTIN AGDATCMDEFINEFUN          defineFun          #-}
  {-# BUILTIN AGDATCMGETTYPE            getType            #-}
  {-# BUILTIN AGDATCMGETDEFINITION      getDefinition      #-}

Metaprogramming
---------------

There are three ways to run a metaprogram (``TC`` computation). To run a
metaprogram in a term position you use a `macro <macros_>`_. To run
metaprograms to create top-level definitions you can use the ``unquoteDecl``
and ``unquoteDef`` primitives (see `Unquoting Declarations`_).

.. _macros:

Macros
~~~~~~

Macros are functions of type ``t₁ → t₂ → .. → Term → TC ⊤`` that are defined in
a ``macro`` block. The last argument is supplied by the type checker and will
be the representation of a metavariable that should be instantiated with the
result of the macro.

Macro application is guided by the type of the macro, where ``Term`` and
``Name`` arguments are quoted before passed to the macro.  Arguments of any
other type are preserved as-is.

For example, the macro application ``f u v w`` where
``f : Term → Name → Bool → Term → TC ⊤`` desugars into::

  unquote (f (quoteTerm u) (quote v) w)

where ``quoteTerm u`` takes a ``u`` of arbitrary type and returns its
representation in the ``Term`` data type, and ``unquote m`` runs a computation
in the ``TC`` monad. Specifically, when checking ``unquote m : A`` for some
type ``A`` the type checker proceeds as follows:

  - Check ``m : Term → TC ⊤``.
  - Create a fresh metavariable ``hole : A``.
  - Let ``qhole : Term`` be the quoted representation of ``hole``.
  - Execute ``m qhole``.
  - Return (the now hopefully instantiated) ``hole``.

.. note::
   The ``quoteTerm`` and ``unquote`` primitives are available in the language,
   but it is recommended to avoid using them in favour of macros.

Limitations:

  - Macros cannot be recursive. This can be worked around by defining the
    recursive function outside the macro block and have the macro call the
    recursive function.

Silly example:

::

    macro
      plus-to-times : Term → Term → TC ⊤
      plus-to-times (def (quote _+_) (a ∷ b ∷ [])) hole = unify hole (def (quote _*_) (a ∷ b ∷ []))
      plus-to-times v hole = unify hole v

    thm : (a b : Nat) → plus-to-times (a + b) ≡ a * b
    thm a b = refl

Macros lets you write tactics that can be applied without any syntactic
overhead. For instance, suppose you have a solver::

  magic : Type → Term

that takes a reflected goal and outputs a proof (when successful). You can then
define the following macro::

  macro
    by-magic : Term → TC ⊤
    by-magic hole =
      bindTC (inferType hole) λ goal →
      unify hole (magic goal)

This lets you apply the magic tactic as a normal function::

  thm : ¬ P ≡ NP
  thm = by-magic

Unquoting Declarations
~~~~~~~~~~~~~~~~~~~~~~

While macros let you write metaprograms to create terms, it is also useful to
be able to create top-level definitions. You can do this from a macro using the
``declareDef`` and ``defineFun`` primitives, but there is no way to bring such
definitions into scope. For this purpose there are two top-level primitives
``unquoteDecl`` and ``unquoteDef`` that runs a ``TC`` computation in a
declaration position. They both have the same form::

  unquoteDecl x₁ .. xₙ = m
  unquoteDef  x₁ .. xₙ = m

except that the list of names can be empty for ``unquoteDecl``, but not for
``unquoteDef``. In both cases ``m`` should have type ``TC ⊤``. The main
difference between the two is that ``unquoteDecl`` requires ``m`` to both
declare (with ``declareDef``) and define (with ``defineFun``) the ``xᵢ``
whereas ``unquoteDef`` expects the ``xᵢ`` to be already declared. In other
words, ``unquoteDecl`` brings the ``xᵢ`` into scope, but ``unquoteDef``
requires them to already be in scope.

In ``m`` the ``xᵢ`` stand for the names of the functions being defined (i.e.
``xᵢ : Name``) rather than the actual functions.

One advantage of ``unquoteDef`` over ``unquoteDecl`` is that
``unquoteDef`` is allowed in mutual blocks, allowing mutually
recursion between generated definitions and hand-written definitions.


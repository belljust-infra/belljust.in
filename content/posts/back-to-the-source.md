---
title: "Back to the Source"
date: 2021-03-22T10:00:00-04:00
publishDate: 2021-03-22T10:00:00-04:00
---

In 2018 I was working for a company that recently acquired a cryptocurrency exchange.
It did around a few hundred million in trading volume every 24hrs, and was widely loved for its early embrace of altcoins.
With the exception of an early Bitcoin hack where ~12% of funds were stolen (but lets be honest - what exchange wasn't hacked in 2014) it was a pretty impressive business.
As these things so often go, it was actually built by a music student who was a self taught programmer.
The code worked pretty well, minus some scaling issues, but it was a sprawling PHP codebase with snowflake components all over - not exactly emanable to collaborative work by dozens of engineers at the acquiring company.

So we went about porting over as much of the infrastructure as we could to our platform.
Wallet management was top of mind here due to security risks.
We had previously built out a secure and scalable infrastructure to manage wallets for an existing product, so it basically came down to supporting multi-tenancy on that platform, doing a migration, and adding a bunch of new chain integrations.

One feature almost all of these exchanges had was support for onchain deposits.
The way many of these work for Ethereum, including in this case, is to create a "smart contract" (which is essentially code and some state deployed to blockchain) that acts as the deposit address.
People send their funds to these contracts, it triggers an event that we're listening for on our platform, we credit their account in the database, then we sweep the funds to some large reserve pool.
Its this last step that got tricky for me.
We needed to port the call to the deposit contract to sweep the funds... but the source code had been lost.

## Ethereum Method Calls

The most widely used language for writing smart contracts in Ethereum is Solidity.
In Solidity, any public method is identified in the Ethereum VM by using a hash of the message signature.
For example, the ERC20 interface defines the following method for transfering `_value` amount of tokens to address `_to`:

```sol
function transfer(address _to, uint256 _value) public returns (bool success)
```

To identify this function, you pass the name and parameter types to the Ethereum hashing function (Keccak-256):

```
> web3.utils.keccak256('transfer(address,uint256)')
'0xa9059cbb2ab09eb219583f4a59a5d0623ade346d962bcd4e46b11da047c9049b'
```

Encoding the data to be sent as a transaction can get a little complex - especially for dynamic types like strings and arrays - but in this case,
1. take the first 4 bytes of the function identifier, `a9059cbb`
2. choose your address and left pad it to 32 bytes, e.g. `000000000000000000000000337c67618968370907da31dAEf3020238D01c9de`
3. choose your amount, hex encode it, and left pad it to 32 bytes, e.g. `10000000000000000000 -> 0000000000000000000000000000000000000000000000008ac7230489e80000`

Putting it all together, you get the data that would be submitted in the transaction:
```
a9059cbb000000000000000000000000337c67618968370907da31dAEf3020238D01c9de0000000000000000000000000000000000000000000000008ac7230489e80000
```

## Hashing and Smashing

Now back to that lost source code.
We had the source for *most* contracts on the legacy platform.
Some of it was in the code repository, others I had to go digging through google docs that were created during the acquisition phase.
It was all there except the earliest Ethereum deposit contracts.
What we did have was some PHP code that looked something like:

```
// Build data to get funds from contract
data = "3904c5c1" + pad32(address) + pad32(amount)
```

Aha! I know the first 4 bytes of the keccak256 hash and some pretty good hints about the argument types are even spelled out for me!
Thankfully I didn't need the actual implementation, I only needed the method signature so I could generate the application binary interface (ABI).
So I went about guessing the method name, running it through the hashing algorithm, then comparing the first 4 bytes.
About an hour later and a dozen or so guesses, we were good to go.

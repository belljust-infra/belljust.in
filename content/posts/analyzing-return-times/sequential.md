---
title: "Analyzing Return Times I - Sequential"
date: 2017-08-28T13:07:05-04:00
mathjax: true
---

Rob Pike has a great [talk](https://www.youtube.com/watch?v=f6kdp27TYZs) about concurrency patterns in Go.
One particularly interesting part is near the end where he presents a "fake" Google Search example.
Using a mock search that simulates a service call with a random wait, he shows three ways to aggregrate the results, each method faster and more interesting than the last.

What I want to add to this discussion, in my next few posts, is an analysis of the return times we can expect from each of these patterns.
In this post, we're going to look at how to:

- model the mocked service as a random variable,
- model the sequential aggregation of three mocked services and,
- use these models to make predictions about the user experience

## fakeSearch

Our mock service is implemented in the `fakeSearch` function.

{{< highlight go >}}
func fakeSearch(kind string) Search {
  return func(query string) Result {
    time.Sleep(time.Duration(rand.Intn(1000)) * time.Millisecond)
  }
}
{{< /highlight >}}


Our `fakeSearch` function waits for some time between 0 and 1000ms, with every time in between being equally likely[^1].
This allows us to model the time to complete a `fakeSearch` as a uniformly distributed random variable, X, on the interval \\([0, 1]\\) (seconds).

$$
f_X(x) = 
\begin{cases}
1,             & \text{if } 0 \leq x \leq 1 \\\\\\
0,             & \text{otherwise}
\end{cases}
$$

This is the probability density function (PDF) of X.
It tells us the _relative likelihood_ the random variable, X, will equal a particular sample, x.

This is not to be confused with _absolute likelihood_.
In fact, there is 0 probability X takes any exact value of x because there are infinitely many points between 0 and 1.
Rather, the PDF can tell us how likely one sample is to appear compared to another.

Notice that, because each time is equally likely, the answer is the same for all values of x between 0 and 1.
Outside 0 and 1, the probability is 0 because we know it certainly cannot be faster than instaneous and it will not take longer than 1 second.

### Aggregate
One search is boring though.
How about we aggregate search results from querying web, image, and video.
The simplest method is making each request sequentially then appending the results:

{{< highlight go >}}
Web   := fakeSearch("web")
Image := fakeSearch("image")
Video := fakeSearch("video")

func GoogleSerial(query string) (results []Result) {
  results = append(results, Web(query))
  results = append(results, Image(query))
  results = append(results, Video(query))
  return
}
{{< /highlight >}}

Because we wait for the previous one to finish, the total time is the sum of all three searches which we will model as another random variable, \\(Y_{sequential}\\).

$$ Y_{sequential} = \sum _{i=1}^n X_i $$

It is feasible to find the distribution of \\(Y_{sequential}\\) using the convolution of \\(f_X(x)\\) with itself and then again with the result of the first convolution.
Luckily for us, however, the result is well established by the [Irwin-Hall distribution](https://en.wikipedia.org/wiki/Irwin%E2%80%93Hall_distribution) for all values of \\(n\\).
For \\(n = 3\\), it turns out to be:
$$
f_Y(y) =
\begin{cases}
\frac{1}{2}y^2              & 0 \leq y \leq 1 \\\\\\
\frac{1}{2}(-2y^2 + 6y - 3) & 1 \leq y \leq 2 \\\\\\
\frac{1}{2}(y^2 - 6y + 9)   & 2 \leq y \leq 3 \\\\\\
0                           & \text{otherwise} \\\\\\
\end{cases}
$$

## What can we do with this info?

Well maybe we find out most people won't use our search if it takes more than 1.5 seconds.
In that case, we want to know the probability our service will respond in at least that amount of time. 

To do that we can integrate the PDF up to 1.5secs.
$$
\int_{-\infty}^{1.5} f_Y(y) dy
$$

The probability the response is less than 0 seconds is 0, so we can adjust the lower bound.
We will also have to split the integral up to respect the piecewise nature of \\(f_Y\\).

$$
\begin{align} 
\int_0^{1.5} f_Y(y) dy & = \int_0^1 \frac{1}{2} y^2 dy + \int_1^{1.5} \frac{1}{2}(-2y^2 + 6y - 3) dy \\\\\\
\\\\\\
                       & = 0.5625 - 0.0625 = 0.5
\end{align}
$$

This means we can expect half of all users to wait longer than 1.5 seconds to get their search results.
Not so good.
To make matters worse, our wait times will keep getting longer with every new search service we add!

Running an experiment with 2000 samples, I got relatively close to this result; 46.0% of queries completed in 1.5 seconds or less.
I suspect the difference in theoretical and experimental results is due to some unaccounted constant overhead, e.g. appending results, building strings.

## What next?

In the next post, we will introduce the concurrent method and see how it compares to our sequential search method.

- [HackerNews](https://news.ycombinator.com/item?id=15188268) discussion

[^1]: It's worth noting that a uniform distribution for a service call delay isn't realistic. A more accurate model might be a [log-normal distribution](https://stats.stackexchange.com/a/46374).
